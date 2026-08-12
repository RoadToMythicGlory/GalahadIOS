import Foundation

/// Layered coordinator for the Phase 2 harness.
/// Capture → Normalize → Encode → Mux → Transport.
/// Does not embed GStreamer, reconnect policy for encoders, or UI concerns.
public actor FeasibilityPipelineCoordinator: PipelineCoordinator {
    public private(set) var status = StreamStatus()

    private var encoder: VideoEncoder?
    private var normalizer: FrameNormalizer?
    private var muxer: MpegTsMuxer?
    private var transport: SrtCallerTransport?
    private var profile: VideoProfile?
    private var framesSubmitted: UInt64 = 0
    private var framesEncoded: UInt64 = 0
    private var bytesEmitted: UInt64 = 0
    private var warmUpFrames: UInt64 = 0
    private var runStarted: ContinuousClock.Instant?
    private var encoderLatencySum: Duration = .zero
    private var endToEndLatencySum: Duration = .zero
    private var latencySamples: UInt64 = 0

    public init() {}

    public func start(
        profile: VideoProfile,
        encoder: VideoEncoder,
        normalizer: FrameNormalizer,
        muxer: MpegTsMuxer,
        transport: SrtCallerTransport
    ) async throws {
        status.state = .starting
        self.profile = profile
        self.encoder = encoder
        self.normalizer = normalizer
        self.muxer = muxer
        self.transport = transport
        framesSubmitted = 0
        framesEncoded = 0
        bytesEmitted = 0
        warmUpFrames = 0
        encoderLatencySum = .zero
        endToEndLatencySum = .zero
        latencySamples = 0

        try await normalizer.prepare(profile: profile)
        try await encoder.configure(
            profile: profile,
            inputFormat: normalizer.outputFormat,
            targetKbps: profile.targetKbps
        )
        try await muxer.configure(profile: profile, includeAudio: false)
        try await transport.connect()
        runStarted = .now
        status.state = .streaming
        status.encoderName = encoder.name
        status.captureBackend = "feasibility-test-pattern"
    }

    public func submitRawFrame(
        raw: Data,
        width: Int,
        height: Int,
        inputFormat: PixelFormat,
        presentationTime: Duration
    ) async throws {
        guard
            let normalizer,
            let encoder,
            let muxer,
            let transport,
            status.state == .streaming || status.state == .degraded
        else {
            throw MediaCoreError.notConfigured("PipelineCoordinator")
        }

        let captureTS = ContinuousClock.now
        framesSubmitted += 1
        let normalized = try await normalizer.normalize(
            raw: raw,
            width: width,
            height: height,
            inputFormat: inputFormat,
            presentationTime: presentationTime,
            captureTimestamp: captureTS
        )
        guard let encoded = try await encoder.encode(normalized) else {
            return // encoder dropped the frame; counted via framesSubmitted only
        }
        framesEncoded += 1
        if let chunk = try await muxer.pushVideo(encoded) {
            try await transport.send(mpegTsChunk: chunk)
            bytesEmitted += UInt64(chunk.count)
        }

        let e2e = ContinuousClock.now - captureTS
        encoderLatencySum += encoded.encoderLatency
        endToEndLatencySum += e2e
        latencySamples += 1

        // Warm-up: first 2 seconds of frames are ignored for drop accounting.
        if let profile, warmUpFrames < UInt64(profile.frameRate * 2) {
            warmUpFrames += 1
        }
    }

    public func stop() async {
        if let muxer {
            _ = try? await muxer.finalize()
            await muxer.teardown()
        }
        if let encoder { await encoder.teardown() }
        if let normalizer { await normalizer.teardown() }
        if let transport { await transport.disconnect() }
        status.state = .idle
        self.encoder = nil
        self.normalizer = nil
        self.muxer = nil
        self.transport = nil
    }

    public func snapshotMetrics() -> FeasibilityRunMetrics {
        let elapsed = runStarted.map { ContinuousClock.now - $0 } ?? .zero
        let elapsedSeconds = max(durationSeconds(elapsed), 0.001)
        let avgEncoderMs = latencySamples == 0 ? 0 : durationMilliseconds(encoderLatencySum) / Double(latencySamples)
        let avgE2EMs = latencySamples == 0 ? 0 : durationMilliseconds(endToEndLatencySum) / Double(latencySamples)
        let measuredFps = Double(framesEncoded) / elapsedSeconds
        let bitrateMbps = (Double(bytesEmitted) * 8.0) / (elapsedSeconds * 1_000_000.0)

        return FeasibilityRunMetrics(
            profileID: profile?.id ?? "unknown",
            framesSubmitted: framesSubmitted,
            framesEncoded: framesEncoded,
            warmUpFrames: warmUpFrames,
            elapsedSeconds: elapsedSeconds,
            measuredFps: measuredFps,
            bitrateMbps: bitrateMbps,
            averageEncoderLatencyMs: avgEncoderMs,
            averageEndToEndLatencyMs: avgE2EMs,
            bytesEmitted: bytesEmitted
        )
    }
}

public struct FeasibilityRunMetrics: Codable, Sendable, Equatable {
    public var profileID: String
    public var framesSubmitted: UInt64
    public var framesEncoded: UInt64
    public var warmUpFrames: UInt64
    public var elapsedSeconds: Double
    public var measuredFps: Double
    public var bitrateMbps: Double
    public var averageEncoderLatencyMs: Double
    public var averageEndToEndLatencyMs: Double
    public var bytesEmitted: UInt64
}

func durationSeconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1e18
}

func durationMilliseconds(_ duration: Duration) -> Double {
    durationSeconds(duration) * 1000.0
}
