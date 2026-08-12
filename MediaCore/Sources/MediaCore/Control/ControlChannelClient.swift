import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent forever-reconnect WebSocket control plane.
/// Media streaming is unaffected by control loss and vice versa.
public actor ControlChannelClient {
    public enum ConnectionState: String, Sendable {
        case idle
        case connecting
        case connected
        case reconnecting
    }

    public private(set) var connectionState: ConnectionState = .idle
    public private(set) var lastError: String?

    private var url: URL?
    private var identity: Identity?
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var runLoopTask: Task<Void, Never>?
    private var telemetryTask: Task<Void, Never>?
    private var shouldRun = false
    private var commandHandler: (@Sendable (ServerControlCommand) async -> CommandAck)?
    private var telemetryProvider: (@Sendable () async -> ControlTelemetry)?
    private var logProvider: (@Sendable () async -> [String])?
    private let reconnectPolicy: SrtReconnectPolicy
    private var reconnectAttempt = 0

    public init(reconnectPolicy: SrtReconnectPolicy = .default) {
        self.reconnectPolicy = reconnectPolicy
    }

    public func configure(
        urlString: String?,
        identity: Identity,
        onCommand: @escaping @Sendable (ServerControlCommand) async -> CommandAck,
        telemetry: @escaping @Sendable () async -> ControlTelemetry,
        logs: @escaping @Sendable () async -> [String] = { [] }
    ) {
        self.identity = identity
        self.commandHandler = onCommand
        self.telemetryProvider = telemetry
        self.logProvider = logs
        if let urlString, let url = URL(string: urlString) {
            self.url = url
        } else {
            self.url = nil
        }
    }

    public func start() {
        guard url != nil else {
            connectionState = .idle
            return
        }
        shouldRun = true
        runLoopTask?.cancel()
        runLoopTask = Task { await self.reconnectLoop() }
    }

    public func stop() {
        shouldRun = false
        runLoopTask?.cancel()
        runLoopTask = nil
        telemetryTask?.cancel()
        telemetryTask = nil
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        connectionState = .idle
        reconnectAttempt = 0
    }

    public func sendAck(_ ack: CommandAck) async {
        try? await send(.commandAck(ack))
    }

    private func reconnectLoop() async {
        while shouldRun, !Task.isCancelled {
            guard let url, let identity else {
                connectionState = .idle
                return
            }
            connectionState = reconnectAttempt == 0 ? .connecting : .reconnecting
            let session = URLSession(configuration: .default)
            self.session = session
            let task = session.webSocketTask(with: url)
            self.task = task
            task.resume()

            do {
                try await send(.hello(
                    playerId: identity.playerId,
                    sessionId: identity.sessionId,
                    displayName: identity.displayName
                ))
                connectionState = .connected
                reconnectAttempt = 0
                lastError = nil
                startTelemetry()
                try await receiveLoop()
            } catch {
                lastError = error.localizedDescription
            }

            telemetryTask?.cancel()
            telemetryTask = nil
            task.cancel()
            session.invalidateAndCancel()
            self.task = nil
            self.session = nil

            guard shouldRun else { break }
            reconnectAttempt += 1
            connectionState = .reconnecting
            let delay = reconnectPolicy.delay(forAttempt: reconnectAttempt)
            try? await Task.sleep(for: delay)
        }
    }

    private func startTelemetry() {
        telemetryTask?.cancel()
        telemetryTask = Task {
            while !Task.isCancelled {
                if let provider = telemetryProvider {
                    let snapshot = await provider()
                    try? await send(.telemetry(snapshot))
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func receiveLoop() async throws {
        guard let task else { return }
        while shouldRun, !Task.isCancelled {
            let message = try await task.receive()
            let text: String
            switch message {
            case .string(let s):
                text = s
            case .data(let d):
                text = String(data: d, encoding: .utf8) ?? ""
            @unknown default:
                continue
            }
            guard !text.isEmpty else { continue }
            let command = try ServerControlCommand.parse(text)
            if let handler = commandHandler {
                var ack = await handler(command)
                if case .requestLogUpload = command, let logProvider {
                    let lines = await logProvider()
                    if let identity {
                        try? await send(.logUpload(sessionId: identity.sessionId, lines: lines))
                    }
                    ack = CommandAck(action: command.actionName, ok: true)
                }
                try? await send(.commandAck(ack))
            }
        }
    }

    private func send(_ message: ClientControlMessage) async throws {
        guard let task else {
            throw MediaCoreError.notConfigured("ControlChannelClient")
        }
        let data = try message.jsonData()
        guard let text = String(data: data, encoding: .utf8) else {
            throw MediaCoreError.pipelineFailed("control encode failed")
        }
        try await task.send(.string(text))
    }
}
