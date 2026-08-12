import Foundation

/// Normalized pixel formats accepted by the video encode boundary.
public enum PixelFormat: String, Codable, Sendable, CaseIterable {
    case bgra
    case nv12
    case i420
    case yuy2
    case i422_10le

    public var bytesPerPixelEstimate: Double {
        switch self {
        case .bgra: return 4.0
        case .nv12, .i420: return 1.5
        case .yuy2: return 2.0
        case .i422_10le: return 2.5
        }
    }
}
