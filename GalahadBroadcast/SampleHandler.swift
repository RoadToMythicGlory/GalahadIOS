import Foundation
import MediaCore
import ReplayKit
import CoreMedia
import CoreVideo

/// Extension-owned full pipeline: Normalize → HEVC → Mux → GStreamer SRT + reconnect.
/// Reads destination/profile from the App Group. Does not require the host app foreground.
final class SampleHandler: RPBroadcastSampleHandler {
    private let store = AppGroupStore.shared
    private let coordinator = StreamCoordinator()
    private var started = false
    private var includeMic = true
    private var includeAppAudio = true
    private var audioEncoder: AACAudioEncoder?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        _ = setupInfo
        Task {
            await startPipeline()
        }
    }

    override func broadcastPaused() {}
    override func broadcastResumed() {}

    override func broadcastFinished() {
        started = false
        Task {
            audioEncoder?.reset()
            await coordinator.stop()
            var status = await coordinator.status
            status.state = .idle
            try? await store.saveStatus(status)
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard started else { return }
        switch sampleBufferType {
        case .video:
            handleVideo(sampleBuffer)
        case .audioApp:
            // Single TS audio stream, no mixer yet: app audio wins when enabled.
            guard includeAppAudio else { return }
            audioEncoder?.encode(sampleBuffer: sampleBuffer)
        case .audioMic:
            guard includeMic, !includeAppAudio else { return }
            audioEncoder?.encode(sampleBuffer: sampleBuffer)
        @unknown default:
            break
        }
    }

    private func startPipeline() async {
        let config = await store.loadConfig()
        includeMic = config.audio.microphoneEnabled
        includeAppAudio = config.audio.appAudioEnabled

        let preset = config.qualityPreset
        let profile = preset.asVideoProfile
        let endpoint = config.srtEndpoint
        let hevcOK = VideoToolboxHEVCEncoder.isAvailable()
        let encoderFactory = EncoderFactory(makeEncoder: {
            hevcOK ? VideoToolboxHEVCEncoder() as VideoEncoder : StubHEVCEncoder()
        })

        let factory = StreamCoordinator.LayerFactory(
            makeEncoder: { encoderFactory.make(for: preset) },
            makeNormalizer: { PassthroughFrameNormalizer(format: .bgra) },
            makeMuxer: { MpegTsStreamMuxer() }
        )

        let transport: SrtCallerTransport
        let probe = GStreamerSrtTransport.probe()
        if probe.available {
            transport = GStreamerSrtTransport(endpoint: endpoint)
        } else {
            #if DEBUG
            transport = RecordingSrtTransport(endpoint: endpoint)
            #else
            finishBroadcastWithError(Self.makeError("DEVICE VALIDATION REQUIRED: GStreamer srtsink unavailable"))
            return
            #endif
        }

        #if !DEBUG
        guard hevcOK else {
            finishBroadcastWithError(Self.makeError("DEVICE VALIDATION REQUIRED: VideoToolbox HEVC unavailable"))
            return
        }
        #endif

        if includeMic || includeAppAudio {
            let coordinator = self.coordinator
            audioEncoder = AACAudioEncoder { packet, pts in
                Task {
                    try? await coordinator.submitAudioAAC(packet, presentationTime: pts)
                }
            }
        }

        do {
            try await coordinator.start(
                profile: profile,
                encoder: encoderFactory.make(for: preset),
                normalizer: PassthroughFrameNormalizer(format: .bgra),
                muxer: MpegTsStreamMuxer(),
                transport: transport,
                includeAudio: includeMic || includeAppAudio,
                captureBackend: VideoSource.screen.captureBackendLabel,
                layerFactory: factory
            )
            started = true
            let status = await coordinator.status
            try? await store.saveStatus(status)
        } catch {
            finishBroadcastWithError(Self.makeError(error.localizedDescription))
        }
    }

    private static func makeError(_ message: String) -> NSError {
        NSError(
            domain: "gg.galahad.broadcast",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private var lastStatusSave = ContinuousClock.now

    private func handleVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        // Zero-copy: ReplayKit's pixel buffer goes straight to VideoToolbox.
        let frame = NormalizedFrame(
            payload: .imageBuffer(pixelBuffer),
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            pixelFormat: .bgra,
            presentationTime: AACAudioEncoder.duration(from: pts),
            captureTimestamp: .now,
            stride: CVPixelBufferGetBytesPerRow(pixelBuffer)
        )
        // Throttle App Group status writes to ~1 Hz; they are for host UI only.
        let saveStatus = ContinuousClock.now - lastStatusSave > .seconds(1)
        if saveStatus {
            lastStatusSave = .now
        }
        Task {
            try? await coordinator.submitFrame(frame)
            if saveStatus {
                let status = await coordinator.status
                try? await store.saveStatus(status)
            }
        }
    }
}
