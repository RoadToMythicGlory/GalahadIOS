import Foundation

/// Minimal normalizer used by the feasibility harness when input already matches
/// the encoder's accepted format. Real camera/screen paths will replace this.
public actor PassthroughFrameNormalizer: FrameNormalizer {
    public let supportedInputFormats: [PixelFormat]
    public let outputFormat: PixelFormat

    public init(format: PixelFormat = .i420) {
        self.supportedInputFormats = [format]
        self.outputFormat = format
    }

    public func prepare(profile: VideoProfile) async throws {
        _ = profile
    }

    public func normalize(
        raw: Data,
        width: Int,
        height: Int,
        inputFormat: PixelFormat,
        presentationTime: Duration,
        captureTimestamp: ContinuousClock.Instant
    ) async throws -> NormalizedFrame {
        guard supportedInputFormats.contains(inputFormat) else {
            throw MediaCoreError.unsupportedPixelFormat(inputFormat)
        }
        return NormalizedFrame(
            pixelBuffer: raw,
            width: width,
            height: height,
            pixelFormat: outputFormat,
            presentationTime: presentationTime,
            captureTimestamp: captureTimestamp,
            stride: width
        )
    }

    public func teardown() async {}
}
