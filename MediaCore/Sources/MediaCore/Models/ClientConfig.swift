import Foundation

/// Persistent client configuration mirrored from RHEncoder contracts, iOS-shaped.
/// SRT caller only; no ST 2110 / listener fields.
public struct ClientConfig: Codable, Sendable, Equatable {
    public var playerId: String
    public var displayName: String
    public var destinationHost: String
    public var destinationPort: UInt16
    public var latencyMs: UInt32
    public var presetId: String
    public var videoSource: VideoSource
    public var videoCodec: VideoCodec
    public var audio: AudioConfig
    public var controlChannelURL: String?

    public init(
        playerId: String = ClientConfig.makePlayerId(),
        displayName: String = "",
        destinationHost: String = "",
        destinationPort: UInt16 = 0,
        latencyMs: UInt32 = SrtEndpoint.minimumLatencyMs,
        presetId: String = QualityPreset.defaultPresetId,
        videoSource: VideoSource = .rearCamera,
        videoCodec: VideoCodec = .hevc,
        audio: AudioConfig = AudioConfig(),
        controlChannelURL: String? = nil
    ) {
        self.playerId = playerId
        self.displayName = displayName
        self.destinationHost = destinationHost
        self.destinationPort = destinationPort
        self.latencyMs = max(latencyMs, SrtEndpoint.minimumLatencyMs)
        self.presetId = presetId
        self.videoSource = videoSource
        self.videoCodec = videoCodec
        self.audio = audio
        self.controlChannelURL = controlChannelURL
    }

    public var srtEndpoint: SrtEndpoint {
        SrtEndpoint(host: destinationHost, port: destinationPort, latencyMs: latencyMs)
    }

    public var qualityPreset: QualityPreset {
        QualityPreset.resolveOrDefault(id: presetId)
    }

    public static func makePlayerId() -> String {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        return "player-\(suffix)"
    }

    enum CodingKeys: String, CodingKey {
        case playerId
        case displayName
        case destinationHost
        case destinationPort
        case latencyMs
        case presetId
        case videoSource
        case videoCodec
        case audio
        case controlChannelURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try c.decodeIfPresent(String.self, forKey: .playerId) ?? ClientConfig.makePlayerId()
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        destinationHost = try c.decodeIfPresent(String.self, forKey: .destinationHost) ?? ""
        destinationPort = try c.decodeIfPresent(UInt16.self, forKey: .destinationPort) ?? 0
        let rawLatency = try c.decodeIfPresent(UInt32.self, forKey: .latencyMs) ?? SrtEndpoint.minimumLatencyMs
        latencyMs = max(rawLatency, SrtEndpoint.minimumLatencyMs)
        presetId = try c.decodeIfPresent(String.self, forKey: .presetId) ?? QualityPreset.defaultPresetId
        videoSource = try c.decodeIfPresent(VideoSource.self, forKey: .videoSource) ?? .rearCamera
        videoCodec = try c.decodeIfPresent(VideoCodec.self, forKey: .videoCodec) ?? .hevc
        audio = try c.decodeIfPresent(AudioConfig.self, forKey: .audio) ?? AudioConfig()
        controlChannelURL = try c.decodeIfPresent(String.self, forKey: .controlChannelURL)
    }
}
