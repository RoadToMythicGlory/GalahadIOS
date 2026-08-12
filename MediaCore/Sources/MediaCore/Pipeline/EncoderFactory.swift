import Foundation

/// Builds a `VideoEncoder` configured for a chosen `QualityPreset`.
/// Product hosts supply a VideoToolbox maker; tests use the stub maker.
public struct EncoderFactory: Sendable {
    public typealias Maker = @Sendable () -> VideoEncoder

    private let makeEncoder: Maker

    public init(makeEncoder: @escaping Maker = { StubHEVCEncoder() }) {
        self.makeEncoder = makeEncoder
    }

    /// Create an encoder instance for the preset (caller still invokes `configure`).
    public func make(for preset: QualityPreset) -> VideoEncoder {
        _ = preset
        return makeEncoder()
    }

    /// Create and configure an encoder for the preset in one step.
    public func makeConfigured(
        for preset: QualityPreset,
        inputFormat: PixelFormat
    ) async throws -> VideoEncoder {
        let encoder = make(for: preset)
        try await encoder.configure(
            profile: preset.asVideoProfile,
            inputFormat: inputFormat,
            targetKbps: preset.hevcKbps
        )
        return encoder
    }

    public static let stub = EncoderFactory(makeEncoder: { StubHEVCEncoder() })
}
