import Foundation

/// Video codec for the outgoing stream.
///
/// H.265 (HEVC) is the product default: best quality per bit. H.264 is the
/// "less expensive" option for shaky cellular links — cheaper to decode,
/// universally supported by receivers, and more forgiving when SRT drops
/// packets because decoders resynchronize on the simpler bitstream faster.
public enum VideoCodec: String, Codable, Sendable, CaseIterable {
    case hevc
    case h264

    public var displayName: String {
        switch self {
        case .hevc: return "H.265 (HEVC)"
        case .h264: return "H.264"
        }
    }
}
