import Foundation

/// Encode profile used by coordinators and the feasibility harness.
/// Product targets are H.265 (HEVC) kbps from `QualityPreset`.
public struct VideoProfile: Hashable, Codable, Sendable, Identifiable {
    public enum Scan: String, Codable, Sendable {
        case progressive
        case interlaced
    }

    public let id: String
    public let width: Int
    public let height: Int
    public let frameRate: Int
    public let scan: Scan
    /// Target HEVC bitrate in kilobits per second.
    public let targetKbps: UInt32?

    public init(
        id: String,
        width: Int,
        height: Int,
        frameRate: Int,
        scan: Scan = .progressive,
        targetKbps: UInt32? = nil
    ) {
        self.id = id
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.scan = scan
        self.targetKbps = targetKbps
    }

    public var pixelsPerSecond: Int {
        width * height * frameRate
    }

    /// Feasibility / lab candidates aligned with the product quality catalog.
    public static let gateCandidates: [VideoProfile] = QualityPreset.catalog.map(\.asVideoProfile)

    /// Kept for compatibility with older feasibility helpers; same set as `gateCandidates`.
    public static let gatedUntilMeasured: [VideoProfile] = []
}
