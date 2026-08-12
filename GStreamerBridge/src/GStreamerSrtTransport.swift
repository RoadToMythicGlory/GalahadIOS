import Foundation

#if canImport(MediaCore)
import MediaCore
#endif

/// Production `SrtCallerTransport` backed by GStreamer `srtsink` (caller mode).
///
/// Media path: MPEG-TS bytes → bridge `galahad_gst_srt_*` → GStreamer `appsrc ! srtsink`.
/// Never uses FFmpeg or libsrt outside GStreamer. Reconnect/backoff lives here only
/// (`SrtTransportSupervisor`); coordinators observe `isReconnecting` and do not drive it.
///
/// Requires `has_srtsink` from `galahad_gst_probe_plugins`. When the plugin is missing,
/// callers must surface transport-unavailable / DEVICE VALIDATION REQUIRED — not a
/// fallback to `RecordingSrtTransport` in release builds (`RecordingSrtTransport` is
/// the in-memory CI/lab fake only).
public actor GStreamerSrtTransport: SrtCallerTransport {
    public let endpoint: SrtEndpoint
    public private(set) var isConnected = false
    public private(set) var isReconnecting = false

    private var context: OpaquePointer?
    private let supervisor: SrtTransportSupervisor
    private var cachedPayloadSizes: [Int] = []

    public init(
        endpoint: SrtEndpoint,
        supervisor: SrtTransportSupervisor = SrtTransportSupervisor()
    ) {
        self.endpoint = endpoint
        self.supervisor = supervisor
    }

    deinit {
        if let context {
            galahad_gst_srt_stop(context)
            galahad_gst_context_destroy(context)
        }
    }

    /// Probe whether this binary has the GStreamer SRT plugin (`srtsink`) registered.
    public static func probe() -> (available: Bool, detail: String) {
        var status = GalahadGSTPluginStatus()
        let ok = galahad_gst_probe_plugins(&status)
        let detail = withUnsafePointer(to: status.detail) {
            $0.withMemoryRebound(to: CChar.self, capacity: 512) {
                String(cString: $0)
            }
        }
        return (ok && status.has_srtsink, detail)
    }

    public func connect() async throws {
        try await startSrtPath(markSupervisorConnected: true)
    }

    public func send(mpegTsChunk: Data) async throws {
        if isConnected, let context, push(mpegTsChunk, context: context) {
            refreshObservedSizes()
            return
        }

        // Transport-owned reconnect: backoff, restart GStreamer SRT path, retry once.
        isConnected = false
        isReconnecting = true
        let delay = await supervisor.nextBackoff()
        try await Task.sleep(for: delay)

        do {
            try await startSrtPath(markSupervisorConnected: true)
        } catch {
            // Leave isReconnecting true so StreamCoordinator can observe without
            // owning backoff; do not fall back to FFmpeg.
            throw MediaCoreError.transportUnavailable(error.localizedDescription)
        }

        guard let context, push(mpegTsChunk, context: context) else {
            isConnected = false
            isReconnecting = true
            throw MediaCoreError.transportUnavailable("GStreamer srtsink send failed after reconnect")
        }
        refreshObservedSizes()
    }

    public func disconnect() async {
        stopSrtPath(destroyContext: true)
        isConnected = false
        isReconnecting = false
        cachedPayloadSizes = []
        await supervisor.reset()
    }

    public func observedPayloadSizes() async -> [Int] {
        refreshObservedSizes()
        return cachedPayloadSizes
    }

    // MARK: - Private

    private func startSrtPath(markSupervisorConnected: Bool) async throws {
        guard !endpoint.host.isEmpty, endpoint.port > 0 else {
            throw MediaCoreError.invalidEndpoint(endpoint.callerURL)
        }

        let probe = Self.probe()
        guard probe.available else {
            throw MediaCoreError.transportUnavailable(probe.detail)
        }

        if context == nil {
            context = galahad_gst_context_create()
        }
        guard let context else {
            throw MediaCoreError.transportUnavailable("failed to create GStreamer context")
        }

        // Restart cleanly: stop any prior appsrc/srtsink elements before start.
        _ = galahad_gst_srt_stop(context)

        let uri = endpoint.callerURL
        let started = uri.withCString { cUri in
            galahad_gst_srt_start(context, cUri, Int32(SrtEndpoint.preferredPayloadBytes))
        }
        guard started else {
            isConnected = false
            throw MediaCoreError.deviceValidationRequired
        }

        isConnected = true
        isReconnecting = false
        if markSupervisorConnected {
            await supervisor.markConnected()
        }
    }

    private func stopSrtPath(destroyContext: Bool) {
        guard let context else { return }
        _ = galahad_gst_srt_stop(context)
        if destroyContext {
            galahad_gst_context_destroy(context)
            self.context = nil
        }
    }

    private func push(_ chunk: Data, context: OpaquePointer) -> Bool {
        chunk.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else { return false }
            return galahad_gst_srt_send(context, base, buffer.count)
        }
    }

    private func refreshObservedSizes() {
        guard let context else { return }
        var buffer = [Int32](repeating: 0, count: 256)
        let count = buffer.withUnsafeMutableBufferPointer { ptr in
            galahad_gst_observed_payload_sizes(context, ptr.baseAddress, 256)
        }
        if count > 0 {
            cachedPayloadSizes = buffer.prefix(Int(count)).map { Int($0) }
        }
    }
}
