import AVFoundation
import Foundation
import MediaCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var config: ClientConfig
    @Published var identity: Identity
    @Published var status: StreamStatus = StreamStatus()
    @Published var logs: [String] = []
    @Published var selectablePresets: [SelectablePreset] = []
    @Published var controlState: ControlChannelClient.ConnectionState = .idle
    @Published var lastError: String?
    @Published var isStreaming = false {
        didSet {
            // Auto-lock kills the capture session mid-stream; keep the screen
            // awake while live and restore normal locking when idle.
            UIApplication.shared.isIdleTimerDisabled = isStreaming
        }
    }
    @Published var streamStartedAt: Date?
    /// Last ~30 s of bitrate samples (2 Hz) for the health sparkline.
    @Published var bitrateHistory: [Double] = []

    let camera = CameraCaptureSession()
    let capabilities = CapabilityStore()
    let store = AppGroupStore.shared
    let coordinator = StreamCoordinator()
    let control = ControlChannelClient()

    private var statusTask: Task<Void, Never>?
    private var hevcAvailable = false
    private var orientationObserver: NSObjectProtocol?
    private var cameraTransitionInFlight = false

    init() {
        let loaded = ClientConfig()
        self.config = loaded
        self.identity = Identity(config: loaded)
    }

    func bootstrap() async {
        config = await store.loadConfig()
        try? await store.saveConfig(config) // persist generated playerId on first launch
        identity = Identity(config: config)
        let perms = await camera.requestPermissions()
        await capabilities.setPermissions(camera: perms.camera, microphone: perms.mic)
        let probe = GStreamerSrtTransport.probe()
        await capabilities.setGStreamerSrtAvailable(probe.available, detail: probe.detail)
        hevcAvailable = VideoToolboxHEVCEncoder.isAvailable()
        await capabilities.setEncoderAvailability(stub: true, hevc: hevcAvailable)
        // Runtime capability gate: presets are startable when the device proves
        // hardware HEVC and GStreamer srtsink are actually present.
        if hevcAvailable && probe.available {
            await capabilities.setValidatedPresetIds(Set(QualityPreset.catalog.map(\.id)))
        }
        selectablePresets = await capabilities.selectablePresets(productionOnly: false)
        camera.attach(coordinator: coordinator)
        observeOrientation()
        await wireControlChannel()
        appendLog("bootstrap complete; hevc=\(hevcAvailable) gstreamerSrt=\(probe.available)")
    }

    // MARK: - Orientation

    /// Interface orientation resolved from the device, falling back to the
    /// active scene when the device is flat (faceUp/faceDown/unknown).
    private var interfaceOrientation: UIInterfaceOrientation {
        switch UIDevice.current.orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight // device left == interface right
        case .landscapeRight: return .landscapeLeft
        default:
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            return scene?.interfaceOrientation ?? .portrait
        }
    }

    private func observeOrientation() {
        guard orientationObserver == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.handleOrientationChange()
            }
        }
    }

    private func handleOrientationChange() {
        // Rotate outgoing buffers so the image stays upright. The encoder keeps
        // its fixed 16:9 session; portrait frames are pillarboxed into it by
        // the aspect-fit normalizer, so no restart is needed.
        camera.applyOrientation(interfaceOrientation)
    }

    func saveConfig() async {
        do {
            try await store.saveConfig(config)
            identity = Identity(playerId: config.playerId, sessionId: identity.sessionId, displayName: config.displayName)
            appendLog("config saved")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startCameraStream() async {
        do {
            let preferProduction = !(await capabilities.labStubModeEnabled)
            try await capabilities.assertStartAllowed(presetId: config.presetId, preferProduction: preferProduction)
            await saveConfig()

            let preset = config.qualityPreset
            camera.applyOrientation(interfaceOrientation)

            // The wire format is always the 16:9 catalog profile. Portrait
            // buffers are aspect-fit (pillarboxed) by the normalizer instead
            // of swapping the encoder to 9:16.
            let profile = preset.asVideoProfile
            let codec = effectiveCodec
            let encoderFactory = makeEncoderFactory(codec: codec)
            let factory = StreamCoordinator.LayerFactory(
                makeEncoder: { encoderFactory.make(for: preset) },
                makeNormalizer: { AspectFitFrameNormalizer(format: .nv12) },
                makeMuxer: { MpegTsStreamMuxer(codec: codec) }
            )

            let transport: SrtCallerTransport
            if await capabilities.gstreamerSrtAvailable {
                transport = GStreamerSrtTransport(endpoint: config.srtEndpoint)
            } else {
                #if DEBUG
                transport = RecordingSrtTransport(endpoint: config.srtEndpoint)
                appendLog("DEBUG lab: using RecordingSrtTransport (no GStreamer srtsink)")
                #else
                throw MediaCoreError.deviceValidationRequired
                #endif
            }

            let encoder = encoderFactory.make(for: preset)
            try await coordinator.start(
                profile: profile,
                encoder: encoder,
                normalizer: AspectFitFrameNormalizer(format: .nv12),
                muxer: MpegTsStreamMuxer(codec: codec),
                transport: transport,
                includeAudio: config.audio.microphoneEnabled,
                captureBackend: config.videoSource.captureBackendLabel,
                layerFactory: factory
            )
            try await camera.start(source: config.videoSource)
            isStreaming = true
            streamStartedAt = Date()
            bitrateHistory = []
            startStatusPolling()
            appendLog("camera stream started (\(config.videoSource.rawValue)) preset=\(preset.id) \(preset.hevcKbps)kbps \(codec.rawValue)")
        } catch {
            lastError = error.localizedDescription
            status.lastError = error.localizedDescription
            appendLog("start failed: \(error.localizedDescription)")
        }
    }

    func stopStream() async {
        await camera.stop()
        await coordinator.stop()
        isStreaming = false
        streamStartedAt = nil
        status = await coordinator.status
        try? await store.saveStatus(status)
        statusTask?.cancel()
        appendLog("stream stopped")
    }

    func switchCamera() async {
        guard config.videoSource == .frontCamera || config.videoSource == .rearCamera else { return }
        // Re-entrancy gate: a tap mid-switch used to interleave two full
        // stop/start sequences and corrupt the pipeline. Ignore extra taps.
        guard !cameraTransitionInFlight else { return }
        cameraTransitionInFlight = true
        defer { cameraTransitionInFlight = false }

        config.videoSource = config.videoSource == .frontCamera ? .rearCamera : .frontCamera
        await saveConfig()
        guard isStreaming else { return }
        do {
            // Swap only the capture input. The encoder, muxer, and SRT
            // connection keep running — same dimensions, no reconnect.
            try await camera.start(source: config.videoSource)
            appendLog("switched camera → \(config.videoSource.rawValue)")
        } catch {
            lastError = error.localizedDescription
            appendLog("camera switch failed: \(error.localizedDescription)")
            await stopStream()
        }
    }

    /// H.264 only when the user opted in and the hardware supports it;
    /// otherwise the untouched H.265 path. Muxer and encoder must agree.
    private var effectiveCodec: VideoCodec {
        config.videoCodec == .h264 && VideoToolboxH264Encoder.isAvailable() ? .h264 : .hevc
    }

    private func makeEncoderFactory(codec: VideoCodec) -> EncoderFactory {
        let useHEVC = hevcAvailable
        return EncoderFactory(makeEncoder: {
            if codec == .h264 {
                return VideoToolboxH264Encoder()
            }
            if useHEVC {
                return VideoToolboxHEVCEncoder()
            }
            return StubHEVCEncoder()
        })
    }

    private func startStatusPolling() {
        statusTask?.cancel()
        statusTask = Task {
            while !Task.isCancelled {
                status = await coordinator.status
                controlState = await control.connectionState
                bitrateHistory.append(status.bitrateMbps)
                if bitrateHistory.count > 60 {
                    bitrateHistory.removeFirst(bitrateHistory.count - 60)
                }
                try? await store.saveStatus(status)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func wireControlChannel() async {
        let identitySnapshot = identity
        await control.configure(
            urlString: config.controlChannelURL,
            identity: identitySnapshot,
            onCommand: { [weak self] command in
                guard let self else {
                    return CommandAck(action: command.actionName, ok: false, detail: "no app")
                }
                return await self.handleControlCommand(command)
            },
            telemetry: { [weak self] in
                guard let self else {
                    return ControlTelemetry(
                        playerId: identitySnapshot.playerId,
                        sessionId: identitySnapshot.sessionId,
                        displayName: identitySnapshot.displayName,
                        streaming: false,
                        state: .idle,
                        fps: 0,
                        bitrate: 0,
                        droppedFrames: 0
                    )
                }
                return await self.makeTelemetry()
            },
            logs: { [weak self] in
                await MainActor.run { self?.logs ?? [] }
            }
        )
        await control.start()
    }

    private func makeTelemetry() async -> ControlTelemetry {
        let status = await coordinator.status
        return ControlTelemetry(identity: identity, status: status, source: config.videoSource)
    }

    private func handleControlCommand(_ command: ServerControlCommand) async -> CommandAck {
        switch command {
        case .startStream, .restartStream:
            if config.videoSource == .screen {
                appendLog("control \(command.actionName): user_action_required (broadcast picker)")
                return CommandAck(
                    action: command.actionName,
                    ok: false,
                    detail: CommandAck.userActionRequired
                )
            }
            await startCameraStream()
            return CommandAck(action: command.actionName, ok: isStreaming, detail: lastError)
        case .stopStream:
            await stopStream()
            return CommandAck(action: command.actionName, ok: true)
        case .switchQuality(let preset):
            config.presetId = preset
            await saveConfig()
            appendLog("staged quality \(preset)")
            return CommandAck(action: command.actionName, ok: true, detail: "staged")
        case .requestLogUpload:
            return CommandAck(action: command.actionName, ok: true)
        case .pushConfig(let newConfig):
            config = newConfig
            await saveConfig()
            appendLog("push_config applied")
            return CommandAck(action: command.actionName, ok: true)
        }
    }

    func appendLog(_ line: String) {
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)"
        logs.append(stamped)
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }

    var diagnosticsText: String {
        """
        playerId: \(identity.playerId)
        sessionId: \(identity.sessionId)
        displayName: \(identity.displayName)
        hevc: \(hevcAvailable)
        control: \(controlState.rawValue)
        state: \(status.state.rawValue)
        lastError: \(status.lastError ?? lastError ?? "-")
        logs:
        \(logs.suffix(40).joined(separator: "\n"))
        """
    }
}
