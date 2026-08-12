import Foundation

/// Stable player identity (`playerId` persisted) plus per-launch `sessionId`.
public struct Identity: Codable, Sendable, Equatable {
    public var playerId: String
    public var sessionId: String
    public var displayName: String

    public init(playerId: String, sessionId: String = UUID().uuidString, displayName: String) {
        self.playerId = playerId
        self.sessionId = sessionId
        self.displayName = displayName
    }

    public init(config: ClientConfig) {
        self.playerId = config.playerId
        self.sessionId = UUID().uuidString
        self.displayName = config.displayName
    }
}
