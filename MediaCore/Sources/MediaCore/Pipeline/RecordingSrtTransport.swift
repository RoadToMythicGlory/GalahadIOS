import Foundation

/// In-memory test / CI fake for `SrtCallerTransport`.
///
/// Stores MPEG-TS chunks and simulates 1316-byte payload sizes. Does **not** open
/// a network socket or call GStreamer. Keep this for unit tests and DEBUG lab
/// fallbacks when `srtsink` is unavailable.
///
/// Production / device streaming must use `GStreamerSrtTransport` (GStreamerBridge)
/// with `galahad_gst_srt_*` → `srtsink`. Never substitute FFmpeg for this type.
public actor RecordingSrtTransport: SrtCallerTransport {
    public let endpoint: SrtEndpoint
    public private(set) var isConnected = false
    public var isReconnecting: Bool { reconnectingFlag }

    private var chunks: [Data] = []
    private var payloadSizes: [Int] = []
    private let supervisor: SrtTransportSupervisor
    private var reconnectingFlag = false

    public init(endpoint: SrtEndpoint, supervisor: SrtTransportSupervisor = SrtTransportSupervisor()) {
        self.endpoint = endpoint
        self.supervisor = supervisor
    }

    public func connect() async throws {
        guard !endpoint.host.isEmpty, endpoint.port > 0 else {
            throw MediaCoreError.invalidEndpoint(endpoint.callerURL)
        }
        isConnected = true
        reconnectingFlag = false
        await supervisor.markConnected()
    }

    public func send(mpegTsChunk: Data) async throws {
        if !isConnected {
            throw MediaCoreError.transportNotConnected
        }
        chunks.append(mpegTsChunk)
        // Simulate packing into preferred 1316-byte SRT payloads (7 × 188).
        var remaining = mpegTsChunk.count
        let preferred = SrtEndpoint.preferredPayloadBytes
        while remaining > 0 {
            let size = min(preferred, remaining)
            payloadSizes.append(size)
            remaining -= size
        }
    }

    public func disconnect() async {
        isConnected = false
        reconnectingFlag = false
        await supervisor.reset()
    }

    public func observedPayloadSizes() async -> [Int] {
        payloadSizes
    }

    public func recordedByteCount() -> Int {
        chunks.reduce(0) { $0 + $1.count }
    }

    public func simulateDisconnectAndBackoff() async -> Duration {
        isConnected = false
        reconnectingFlag = true
        return await supervisor.nextBackoff()
    }
}
