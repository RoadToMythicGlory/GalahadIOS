import Foundation

/// Named broadcast quality profile with Galahad-owned HEVC bitrate targets (kbps).
/// Catalog is mobile/5G oriented: 720p30 through 1080p60 — no ≤480, no 4K.
public struct QualityPreset: Codable, Sendable, Equatable, Identifiable, Hashable {
    public enum Scan: String, Codable, Sendable {
        case progressive
        case interlaced
    }

    public let id: String
    public let label: String
    public let width: Int
    public let height: Int
    public let frameRate: Int
    public let scan: Scan
    /// Target video bitrate for H.265 (HEVC), in kilobits per second.
    public let hevcKbps: UInt32

    public init(
        id: String,
        label: String,
        width: Int,
        height: Int,
        frameRate: Int,
        scan: Scan = .progressive,
        hevcKbps: UInt32
    ) {
        self.id = id
        self.label = label
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.scan = scan
        self.hevcKbps = hevcKbps
    }

    public var asVideoProfile: VideoProfile {
        VideoProfile(
            id: id,
            width: width,
            height: height,
            frameRate: frameRate,
            scan: scan == .interlaced ? .interlaced : .progressive,
            targetKbps: hevcKbps
        )
    }

    /// Least demanding preset is the out-of-box default; heavier presets are
    /// opt-in once device evidence exists (repo rule: no unvalidated defaults).
    public static let defaultPresetId = "720p30"

    /// Progressive presets only. Interlaced (1080i50/i60) was removed from the
    /// catalog: VideoToolbox HEVC does not produce true interlaced output, so
    /// offering those presets would silently deliver progressive frames.
    /// Re-scope them if a real interlacing requirement ever materializes.
    public static let catalog: [QualityPreset] = [
        QualityPreset(id: "720p30", label: "720 p30", width: 1280, height: 720, frameRate: 30, hevcKbps: 2500),
        QualityPreset(id: "1080p30", label: "1080 p30", width: 1920, height: 1080, frameRate: 30, hevcKbps: 4500),
        QualityPreset(id: "1080p50", label: "1080 p50", width: 1920, height: 1080, frameRate: 50, hevcKbps: 7000),
        QualityPreset(id: "1080p60", label: "1080 p60", width: 1920, height: 1080, frameRate: 60, hevcKbps: 8400),
    ]

    public static func find(id: String) -> QualityPreset? {
        catalog.first { $0.id == id }
    }

    public static func resolveOrDefault(id: String) -> QualityPreset {
        find(id: id) ?? find(id: defaultPresetId)!
    }
}
