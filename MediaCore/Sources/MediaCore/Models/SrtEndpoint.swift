import Foundation

/// SRT caller topology only. Listener/fan-out is explicitly out of scope.
public struct SrtEndpoint: Codable, Sendable, Equatable {
    public static let minimumLatencyMs: UInt32 = 200
    public static let preferredPayloadBytes: Int = 1316

    public var host: String
    public var port: UInt16
    public var latencyMs: UInt32

    public init(host: String, port: UInt16, latencyMs: UInt32 = minimumLatencyMs) {
        self.host = host
        self.port = port
        self.latencyMs = max(latencyMs, Self.minimumLatencyMs)
    }

    /// Canonical caller URL. Packet size is requested; callers must verify
    /// actual emitted packetization rather than treating this as proof.
    public var callerURL: String {
        "srt://\(host):\(port)?mode=caller&latency=\(latencyMs)&pkt_size=\(Self.preferredPayloadBytes)"
    }
}
