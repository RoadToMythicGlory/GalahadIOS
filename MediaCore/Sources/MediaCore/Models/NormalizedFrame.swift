import Foundation
#if canImport(CoreVideo)
import CoreVideo
#endif

/// Pixel payload of a normalized frame.
///
/// `.imageBuffer` carries the capture `CVPixelBuffer` by reference so the
/// hardware path (AVFoundation/ReplayKit → VideoToolbox) never copies pixel
/// bytes. `.bytes` remains for the pure-Swift harness/tests on any platform.
public enum NormalizedFramePayload: @unchecked Sendable {
    case bytes(Data)
    #if canImport(CoreVideo)
    case imageBuffer(CVPixelBuffer)
    #endif
}

/// Frame that has passed Capture → Frame normalization.
/// MediaCore never exposes encoder-specific buffers across this boundary.
public struct NormalizedFrame: Sendable {
    public let payload: NormalizedFramePayload
    public let width: Int
    public let height: Int
    public let pixelFormat: PixelFormat
    public let presentationTime: Duration
    public let captureTimestamp: ContinuousClock.Instant
    public let stride: Int

    public init(
        payload: NormalizedFramePayload,
        width: Int,
        height: Int,
        pixelFormat: PixelFormat,
        presentationTime: Duration,
        captureTimestamp: ContinuousClock.Instant,
        stride: Int
    ) {
        self.payload = payload
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.presentationTime = presentationTime
        self.captureTimestamp = captureTimestamp
        self.stride = stride
    }

    public init(
        pixelBuffer: Data,
        width: Int,
        height: Int,
        pixelFormat: PixelFormat,
        presentationTime: Duration,
        captureTimestamp: ContinuousClock.Instant,
        stride: Int
    ) {
        self.init(
            payload: .bytes(pixelBuffer),
            width: width,
            height: height,
            pixelFormat: pixelFormat,
            presentationTime: presentationTime,
            captureTimestamp: captureTimestamp,
            stride: stride
        )
    }

    /// Byte payload when present (`.bytes` case); empty for hardware buffers.
    public var pixelBuffer: Data {
        if case .bytes(let data) = payload { return data }
        return Data()
    }
}

/// Encoded access unit produced by any `VideoEncoder` adapter (HEVC Annex-B in product).
public struct EncodedAccessUnit: Sendable {
    public let data: Data
    public let presentationTime: Duration
    public let encodeStarted: ContinuousClock.Instant
    public let encodeFinished: ContinuousClock.Instant
    public let width: Int
    public let height: Int

    public init(
        data: Data,
        presentationTime: Duration,
        encodeStarted: ContinuousClock.Instant,
        encodeFinished: ContinuousClock.Instant,
        width: Int,
        height: Int
    ) {
        self.data = data
        self.presentationTime = presentationTime
        self.encodeStarted = encodeStarted
        self.encodeFinished = encodeFinished
        self.width = width
        self.height = height
    }

    public var encoderLatency: Duration {
        encodeFinished - encodeStarted
    }
}
