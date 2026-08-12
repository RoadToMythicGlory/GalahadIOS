import Foundation

public enum AudioChannelKind: String, Codable, Sendable, Equatable {
    case microphone
    case appAudio
}

public struct AudioChannel: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: AudioChannelKind
    public var enabled: Bool
    public var muted: Bool
    /// Linear gain 0.0...2.0; 1.0 is unity.
    public var gain: Float
    public var label: String?

    public init(
        id: String,
        kind: AudioChannelKind,
        enabled: Bool = true,
        muted: Bool = false,
        gain: Float = 1.0,
        label: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.enabled = enabled
        self.muted = muted
        self.gain = min(max(gain, 0), 2)
        self.label = label
    }

    public var isLive: Bool { enabled && !muted }

    enum CodingKeys: String, CodingKey {
        case id
        case kind = "type"
        case enabled
        case muted
        case gain
        case label
    }
}

/// Mic + app-audio mixer (no Windows per-app process picker).
public struct AudioConfig: Codable, Sendable, Equatable {
    public var sources: [AudioChannel]

    public init(sources: [AudioChannel] = AudioConfig.defaultSources) {
        self.sources = sources
    }

    public static let defaultSources: [AudioChannel] = [
        AudioChannel(id: "microphone", kind: .microphone, label: "Microphone"),
        AudioChannel(id: "appAudio", kind: .appAudio, enabled: true, label: "App audio"),
    ]

    public var microphoneEnabled: Bool {
        sources.first(where: { $0.kind == .microphone })?.isLive ?? false
    }

    public var appAudioEnabled: Bool {
        sources.first(where: { $0.kind == .appAudio })?.isLive ?? false
    }
}
