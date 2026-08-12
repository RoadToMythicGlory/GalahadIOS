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
    @Published var isStreaming = false

    let camera = CameraCaptureSession()
    let capabilities = CapabilityStore()
    let store = AppGroupStore.shared
    let coordinator = StreamCoordinator()
    let control = ControlChannelClient()

    private var statusTask: Task<Void, Never>?
    private var hevcAvailable = false

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
        selectablePresets = await capabilities.selectablePresets(productionOnly: false)
        camera.attach(coordinator: coordinator)
        await wireControlChannel()
        appendLog("bootstrap complete; hevc=\(hevcAvailable) gstreamerSrt=\(probe.available)")
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
            let profile = preset.asVideoProfile
            let encoderFactory = makeEncoderFactory()
            let factory = StreamCoordinator.LayerFactory(
                makeEncoder: { encoderFactory.make(for: preset) },
                makeNormalizer: { PassthroughFrameNormalizer(format: .nv12) },
                makeMuxer: { MpegTsStreamMuxer() }
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
                normalizer: PassthroughFrameNormalizer(format: .nv12),
                muxer: MpegTsStreamMuxer(),
                transport: transport,
                includeAudio: config.audio.microphoneEnabled,
                captureBackend: config.videoSource.captureBackendLabel,
                layerFactory: factory
            )
            try await camera.start(source: config.videoSource)
            isStreaming = true
            startStatusPolling()
            appendLog("camera stream started (\(config.videoSource.rawValue)) preset=\(preset.id) \(preset.hevcKbps)kbps hevc")
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
        status = await coordinator.status
        try? await store.saveStatus(status)
        statusTask?.cancel()
        appendLog("stream stopped")
    }

    func switchCamera() async {
        guard config.videoSource == .frontCamera || config.videoSource == .rearCamera else { return }
        await stopStream()
        config.videoSource = config.videoSource == .frontCamera ? .rearCamera : .frontCamera
        await saveConfig()
        await startCameraStream()
    }

    private func makeEncoderFactory() -> EncoderFactory {
        let useHEVC = hevcAvailable
        return EncoderFactory(makeEncoder: {
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
