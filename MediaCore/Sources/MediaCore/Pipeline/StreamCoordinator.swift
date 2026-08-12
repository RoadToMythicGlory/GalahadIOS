import Foundation

/// Product pipeline coordinator: Capture → Normalize → Encode → Mux → Transport.
/// Does not own SRT reconnect (transport only). Encoder/mux failures recreate those layers.
public actor StreamCoordinator: PipelineCoordinator {
    public private(set) var status = StreamStatus()

    private var encoder: VideoEncoder?
    private var normalizer: FrameNormalizer?
    private var muxer: MpegTsMuxer?
    private var transport: SrtCallerTransport?
    private var profile: VideoProfile?
    private var includeAudio = false
    private var framesSubmitted: UInt64 = 0
    private var framesEncoded: UInt64 = 0
    private var bytesEmitted: UInt64 = 0
    private var runStarted: ContinuousClock.Instant?
    private var layerFactory: LayerFactory?

    public struct LayerFactory: Sendable {
        public var makeEncoder: @Sendable () -> VideoEncoder
        public var makeNormalizer: @Sendable () -> FrameNormalizer
        public var makeMuxer: @Sendable () -> MpegTsMuxer

        public init(
            makeEncoder: @escaping @Sendable () -> VideoEncoder,
            makeNormalizer: @escaping @Sendable () -> FrameNormalizer,
            makeMuxer: @escaping @Sendable () -> MpegTsMuxer
        ) {
            self.makeEncoder = makeEncoder
            self.makeNormalizer = makeNormalizer
            self.makeMuxer = makeMuxer
        }
    }

    public init() {}

    public func start(
        profile: VideoProfile,
        encoder: VideoEncoder,
        normalizer: FrameNormalizer,
        muxer: MpegTsMuxer,
        transport: SrtCallerTransport
    ) async throws {
        try await start(
            profile: profile,
            encoder: encoder,
            normalizer: normalizer,
            muxer: muxer,
            transport: transport,
            includeAudio: false,
            captureBackend: nil,
            layerFactory: nil
        )
    }

    public func start(
        profile: VideoProfile,
        encoder: VideoEncoder,
        normalizer: FrameNormalizer,
        muxer: MpegTsMuxer,
        transport: SrtCallerTransport,
        includeAudio: Bool,
        captureBackend: String?,
        layerFactory: LayerFactory?
    ) async throws {
        status = StreamStatus(state: .starting, encoderName: encoder.name, captureBackend: captureBackend)
        self.profile = profile
        self.encoder = encoder
        self.normalizer = normalizer
        self.muxer = muxer
        self.transport = transport
        self.includeAudio = includeAudio
        self.layerFactory = layerFactory
        framesSubmitted = 0
        framesEncoded = 0
        bytesEmitted = 0

        do {
            try await normalizer.prepare(profile: profile)
            try await encoder.configure(
                profile: profile,
                inputFormat: normalizer.outputFormat,
                targetKbps: profile.targetKbps
            )
            try await muxer.configure(profile: profile, includeAudio: includeAudio)
            try await transport.connect()
            runStarted = .now
            status.state = .streaming
            status.encoderName = encoder.name
            status.captureBackend = captureBackend
            status.lastError = nil
        } catch {
            status.state = .failed
            status.lastError = error.localizedDescription
            await teardownLayers(keepTransport: false)
            throw error
        }
    }

    public func submitRawFrame(
        raw: Data,
        width: Int,
        height: Int,
        inputFormat: PixelFormat,
        presentationTime: Duration
    ) async throws {
        if let transport, await transport.isReconnecting {
            status.state = .reconnecting
        }

        guard
            let normalizer,
            let encoder,
            let muxer,
            let transport,
            status.state == .streaming || status.state == .degraded || status.state == .reconnecting
        else {
            throw MediaCoreError.notConfigured("StreamCoordinator")
        }

        let captureTS = ContinuousClock.now
        framesSubmitted += 1

        do {
            let normalized = try await normalizer.normalize(
                raw: raw,
                width: width,
                height: height,
                inputFormat: inputFormat,
                presentationTime: presentationTime,
                captureTimestamp: captureTS
            )
            try await encodeMuxSend(normalized, encoder: encoder, muxer: muxer, transport: transport)
        } catch {
            try await handleLayerFailure(error)
        }
    }

    /// Zero-copy path for already-normalized frames (capture hands the hardware
    /// pixel buffer straight through; no `Data` copy, no normalizer hop).
    public func submitFrame(_ frame: NormalizedFrame) async throws {
        if let transport, await transport.isReconnecting {
            status.state = .reconnecting
        }

        guard
            let encoder,
            let muxer,
            let transport,
            status.state == .streaming || status.state == .degraded || status.state == .reconnecting
        else {
            throw MediaCoreError.notConfigured("StreamCoordinator")
        }

        framesSubmitted += 1
        do {
            try await encodeMuxSend(frame, encoder: encoder, muxer: muxer, transport: transport)
        } catch {
            try await handleLayerFailure(error)
        }
    }

    private func encodeMuxSend(
        _ frame: NormalizedFrame,
        encoder: VideoEncoder,
        muxer: MpegTsMuxer,
        transport: SrtCallerTransport
    ) async throws {
        guard let encoded = try await encoder.encode(frame) else {
            // Encoder dropped the frame under real-time pressure; not a failure.
            refreshMetrics()
            return
        }
        framesEncoded += 1
        if let chunk = try await muxer.pushVideo(encoded) {
            try await sendWithTransportReconnectObservation(transport: transport, chunk: chunk)
            bytesEmitted += UInt64(chunk.count)
        }
        refreshMetrics()
        if status.state == .reconnecting, await transport.isConnected {
            status.state = .streaming
        } else if status.state != .reconnecting {
            status.state = .streaming
        }
    }

    public func submitAudioAAC(_ packet: Data, presentationTime: Duration) async throws {
        guard
            includeAudio,
            let muxer,
            let transport,
            status.state == .streaming || status.state == .degraded || status.state == .reconnecting
        else {
            return
        }
        do {
            if let chunk = try await muxer.pushAudioAAC(packet, presentationTime: presentationTime) {
                try await sendWithTransportReconnectObservation(transport: transport, chunk: chunk)
                bytesEmitted += UInt64(chunk.count)
            }
        } catch {
            try await handleLayerFailure(error)
        }
    }

    public func markDegraded(_ reason: String) {
        guard status.state == .streaming || status.state == .degraded else { return }
        status.state = .degraded
        status.lastError = reason
    }

    public func stop() async {
        await teardownLayers(keepTransport: false)
        status.state = .idle
        status.fps = 0
        status.bitrateMbps = 0
        runStarted = nil
    }

    private func sendWithTransportReconnectObservation(
        transport: SrtCallerTransport,
        chunk: Data
    ) async throws {
        do {
            try await transport.send(mpegTsChunk: chunk)
        } catch {
            if await transport.isReconnecting {
                status.state = .reconnecting
                status.lastError = error.localizedDescription
                return
            }
            throw error
        }
    }

    private func handleLayerFailure(_ error: Error) async throws {
        status.lastError = error.localizedDescription
        // Transport reconnect is owned by transport; coordinator only recreates encode/mux.
        if let transport, await transport.isReconnecting {
            status.state = .reconnecting
            return
        }
        guard let factory = layerFactory, let profile else {
            status.state = .failed
            await teardownLayers(keepTransport: false)
            throw MediaCoreError.pipelineFailed(error.localizedDescription)
        }

        if let encoder { await encoder.teardown() }
        if let muxer {
            _ = try? await muxer.finalize()
            await muxer.teardown()
        }
        if let normalizer { await normalizer.teardown() }

        let newNormalizer = factory.makeNormalizer()
        let newEncoder = factory.makeEncoder()
        let newMuxer = factory.makeMuxer()
        do {
            try await newNormalizer.prepare(profile: profile)
            try await newEncoder.configure(
                profile: profile,
                inputFormat: newNormalizer.outputFormat,
                targetKbps: profile.targetKbps
            )
            try await newMuxer.configure(profile: profile, includeAudio: includeAudio)
            self.normalizer = newNormalizer
            self.encoder = newEncoder
            self.muxer = newMuxer
            status.state = .streaming
            status.encoderName = newEncoder.name
            status.lastError = "recreated encode/mux after: \(error.localizedDescription)"
        } catch {
            status.state = .failed
            status.lastError = error.localizedDescription
            await teardownLayers(keepTransport: false)
            throw MediaCoreError.pipelineFailed(error.localizedDescription)
        }
    }

    private func teardownLayers(keepTransport: Bool) async {
        if let muxer {
            _ = try? await muxer.finalize()
            await muxer.teardown()
        }
        if let encoder { await encoder.teardown() }
        if let normalizer { await normalizer.teardown() }
        if !keepTransport, let transport {
            await transport.disconnect()
            self.transport = nil
        }
        self.encoder = nil
        self.normalizer = nil
        self.muxer = nil
    }

    private func refreshMetrics() {
        guard let runStarted else { return }
        let elapsed = max(durationSeconds(ContinuousClock.now - runStarted), 0.001)
        status.fps = Double(framesEncoded) / elapsed
        status.bitrateMbps = (Double(bytesEmitted) * 8.0) / (elapsed * 1_000_000.0)
        if framesSubmitted > framesEncoded {
            status.droppedFrames = framesSubmitted - framesEncoded
        }
    }
}
