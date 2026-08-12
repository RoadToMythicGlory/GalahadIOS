import AVFoundation
import CoreMedia
import Foundation
import MediaCore
import UIKit

/// Host-only AVFoundation front/rear + mic capture into StreamCoordinator.
///
/// Video flows zero-copy: the capture `CVPixelBuffer` (NV12) is wrapped in
/// `NormalizedFrame.payload.imageBuffer` and handed to VideoToolbox without
/// any byte copies. A bounded frame channel (newest-2) decouples the capture
/// callback from encoder backpressure so late frames are dropped, not queued.
/// Mic audio goes through `AACAudioEncoder` into `submitAudioAAC`.
final class CameraCaptureSession: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "gg.galahad.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var currentPosition: AVCaptureDevice.Position = .back
    nonisolated(unsafe) private var coordinator: StreamCoordinator?
    nonisolated(unsafe) private var audioEncoder: AACAudioEncoder?
    private var interruptionObserver: NSObjectProtocol?

    // Frame channel state (accessed from the video delegate queue and the pump task).
    nonisolated(unsafe) private var frameContinuation: AsyncStream<NormalizedFrame>.Continuation?
    private var framePumpTask: Task<Void, Never>?

    /// Rotation applied to outgoing buffers; written on the session queue,
    /// seeded before start so new sessions come up in the right orientation.
    nonisolated(unsafe) private var pendingRotationAngle: CGFloat = 90 // portrait default

    func attach(coordinator: StreamCoordinator) {
        self.coordinator = coordinator
        if audioEncoder == nil {
            audioEncoder = AACAudioEncoder { [weak coordinator] packet, pts in
                guard let coordinator else { return }
                Task {
                    try? await coordinator.submitAudioAAC(packet, presentationTime: pts)
                }
            }
        }
        if interruptionObserver == nil {
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] note in
                self?.handleInterruption(note)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        switch type {
        case .began:
            sessionQueue.async {
                if self.session.isRunning {
                    self.session.stopRunning()
                }
            }
        case .ended:
            sessionQueue.async {
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        @unknown default:
            break
        }
    }

    func requestPermissions() async -> (camera: Bool, mic: Bool) {
        let camera = await AVCaptureDevice.requestAccess(for: .video)
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        return (camera, mic)
    }

    func start(source: VideoSource) async throws {
        let position: AVCaptureDevice.Position = source == .frontCamera ? .front : .back
        try await restart(position: position)
    }

    func switchCamera() async throws {
        let next: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        try await restart(position: next)
    }

    /// Async stop: session teardown runs on the session queue without blocking
    /// the caller's executor (no `sessionQueue.sync` from the main actor).
    func stop() async {
        stopFrameChannel()
        audioEncoder?.reset()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                self.session.beginConfiguration()
                self.session.inputs.forEach { self.session.removeInput($0) }
                self.session.outputs.forEach { self.session.removeOutput($0) }
                self.session.commitConfiguration()
                cont.resume()
            }
        }
        await MainActor.run {
            self.isRunning = false
            self.previewLayer = nil
        }
    }

    private func restart(position: AVCaptureDevice.Position) async throws {
        await stop()
        currentPosition = position
        startFrameChannel()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureSession(position: position)
                    self.session.startRunning()
                    DispatchQueue.main.async {
                        let layer = AVCaptureVideoPreviewLayer(session: self.session)
                        layer.videoGravity = .resizeAspectFill
                        self.previewLayer = layer
                        self.isRunning = true
                        cont.resume()
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.lastError = error.localizedDescription
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }

    // MARK: - Frame channel

    private func startFrameChannel() {
        guard let coordinator else { return }
        let (stream, continuation) = AsyncStream.makeStream(
            of: NormalizedFrame.self,
            bufferingPolicy: .bufferingNewest(2)
        )
        frameContinuation = continuation
        framePumpTask = Task {
            for await frame in stream {
                try? await coordinator.submitFrame(frame)
            }
        }
    }

    private func stopFrameChannel() {
        frameContinuation?.finish()
        frameContinuation = nil
        framePumpTask?.cancel()
        framePumpTask = nil
    }

    // MARK: - Session graph

    private func configureSession(position: AVCaptureDevice.Position) throws {
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            session.commitConfiguration()
            throw MediaCoreError.notConfigured("camera \(position.rawValue)")
        }
        let videoInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(videoInput) else {
            session.commitConfiguration()
            throw MediaCoreError.notConfigured("video input")
        }
        session.addInput(videoInput)

        if let mic = AVCaptureDevice.default(for: .audio) {
            let audioInput = try AVCaptureDeviceInput(device: mic)
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }
        }

        videoOutput.alwaysDiscardsLateVideoFrames = true
        // NV12 (bi-planar 4:2:0): the camera's native format and VideoToolbox's
        // preferred input — half the memory bandwidth of BGRA, no conversion.
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "gg.galahad.camera.video"))
        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw MediaCoreError.notConfigured("video output")
        }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = position == .front
            }
            if connection.isVideoRotationAngleSupported(pendingRotationAngle) {
                connection.videoRotationAngle = pendingRotationAngle
            }
        }

        audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "gg.galahad.camera.audio"))
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
        }

        session.commitConfiguration()
    }

    static func rotationAngle(for orientation: UIInterfaceOrientation) -> CGFloat {
        switch orientation {
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft: return 180
        case .landscapeRight: return 0
        default: return 90
        }
    }

    func applyOrientation(_ orientation: UIInterfaceOrientation) {
        let angle = Self.rotationAngle(for: orientation)
        sessionQueue.async {
            self.pendingRotationAngle = angle
            guard let connection = self.videoOutput.connection(with: .video) else { return }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }
}

extension CameraCaptureSession: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output is AVCaptureVideoDataOutput {
            handleVideo(sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            audioEncoder?.encode(sampleBuffer: sampleBuffer)
        }
    }

    private func handleVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let frame = NormalizedFrame(
            payload: .imageBuffer(pixelBuffer),
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            pixelFormat: .nv12,
            presentationTime: AACAudioEncoder.duration(from: pts),
            captureTimestamp: .now,
            stride: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        )
        // Bounded channel: if the encoder can't keep up, old frames are replaced.
        frameContinuation?.yield(frame)
    }
}
