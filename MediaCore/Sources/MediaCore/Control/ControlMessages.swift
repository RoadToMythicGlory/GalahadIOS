import Foundation

/// Telemetry pushed to the control plane at ~1 Hz.
public struct ControlTelemetry: Codable, Sendable, Equatable {
    public var playerId: String
    public var sessionId: String
    public var displayName: String
    public var source: String?
    public var streaming: Bool
    public var state: StreamLifecycle
    public var fps: UInt32
    public var bitrate: UInt32
    public var droppedFrames: UInt64
    public var encoder: String?
    public var captureBackend: String?
    public var lastError: String?

    public init(
        playerId: String,
        sessionId: String,
        displayName: String,
        source: String? = nil,
        streaming: Bool,
        state: StreamLifecycle,
        fps: UInt32,
        bitrate: UInt32,
        droppedFrames: UInt64,
        encoder: String? = nil,
        captureBackend: String? = nil,
        lastError: String? = nil
    ) {
        self.playerId = playerId
        self.sessionId = sessionId
        self.displayName = displayName
        self.source = source
        self.streaming = streaming
        self.state = state
        self.fps = fps
        self.bitrate = bitrate
        self.droppedFrames = droppedFrames
        self.encoder = encoder
        self.captureBackend = captureBackend
        self.lastError = lastError
    }

    public init(identity: Identity, status: StreamStatus, source: VideoSource?) {
        self.playerId = identity.playerId
        self.sessionId = identity.sessionId
        self.displayName = identity.displayName
        self.source = source?.rawValue
        self.streaming = status.state == .streaming || status.state == .degraded
        self.state = status.state
        self.fps = UInt32(max(0, status.fps.rounded()))
        self.bitrate = UInt32(max(0, (status.bitrateMbps * 1000).rounded()))
        self.droppedFrames = status.droppedFrames
        self.encoder = status.encoderName
        self.captureBackend = status.captureBackend
        self.lastError = status.lastError
    }
}

public struct CommandAck: Codable, Sendable, Equatable {
    public var action: String
    public var ok: Bool
    public var detail: String?

    public init(action: String, ok: Bool, detail: String? = nil) {
        self.action = action
        self.ok = ok
        self.detail = detail
    }

    public static let userActionRequired = "user_action_required"
}

public enum ClientControlMessage: Sendable, Equatable {
    case hello(playerId: String, sessionId: String, displayName: String)
    case telemetry(ControlTelemetry)
    case commandAck(CommandAck)
    case logUpload(sessionId: String, lines: [String])

    public func jsonData() throws -> Data {
        try ControlJSON.encodeClientMessage(self)
    }
}

public enum ServerControlCommand: Sendable, Equatable {
    case startStream
    case stopStream
    case restartStream
    case switchQuality(preset: String)
    case requestLogUpload
    case pushConfig(config: ClientConfig)

    public var actionName: String {
        switch self {
        case .startStream: return "start_stream"
        case .stopStream: return "stop_stream"
        case .restartStream: return "restart_stream"
        case .switchQuality: return "switch_quality"
        case .requestLogUpload: return "request_log_upload"
        case .pushConfig: return "push_config"
        }
    }

    public static func parse(_ raw: String) throws -> ServerControlCommand {
        try ControlJSON.decodeServerCommand(raw)
    }
}

enum ControlJSON {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func encodeClientMessage(_ message: ClientControlMessage) throws -> Data {
        switch message {
        case let .hello(playerId, sessionId, displayName):
            return try encoder.encode(HelloBody(
                type: "hello",
                playerId: playerId,
                sessionId: sessionId,
                displayName: displayName
            ))
        case let .telemetry(telemetry):
            let payload = try encoder.encode(telemetry)
            var obj = try JSONSerialization.jsonObject(with: payload) as! [String: Any]
            obj["type"] = "telemetry"
            return try JSONSerialization.data(withJSONObject: obj)
        case let .commandAck(ack):
            let payload = try encoder.encode(ack)
            var obj = try JSONSerialization.jsonObject(with: payload) as! [String: Any]
            obj["type"] = "command_ack"
            return try JSONSerialization.data(withJSONObject: obj)
        case let .logUpload(sessionId, lines):
            return try encoder.encode(LogUploadBody(
                type: "log_upload",
                sessionId: sessionId,
                lines: lines
            ))
        }
    }

    static func decodeServerCommand(_ raw: String) throws -> ServerControlCommand {
        guard let data = raw.data(using: .utf8) else {
            throw MediaCoreError.pipelineFailed("control command not UTF-8")
        }
        let envelope = try decoder.decode(ServerCommandEnvelope.self, from: data)
        switch envelope.action {
        case "start_stream":
            return .startStream
        case "stop_stream":
            return .stopStream
        case "restart_stream":
            return .restartStream
        case "switch_quality":
            guard let preset = envelope.preset, !preset.isEmpty else {
                throw MediaCoreError.pipelineFailed("switch_quality missing preset")
            }
            return .switchQuality(preset: preset)
        case "request_log_upload":
            return .requestLogUpload
        case "push_config":
            guard let config = envelope.config else {
                throw MediaCoreError.pipelineFailed("push_config missing config")
            }
            return .pushConfig(config: config)
        default:
            throw MediaCoreError.pipelineFailed("unrecognized command '\(envelope.action)'")
        }
    }

    private struct ServerCommandEnvelope: Decodable {
        var action: String
        var preset: String?
        var config: ClientConfig?
    }

    private struct HelloBody: Encodable {
        var type: String
        var playerId: String
        var sessionId: String
        var displayName: String
    }

    private struct LogUploadBody: Encodable {
        var type: String
        var sessionId: String
        var lines: [String]
    }
}
