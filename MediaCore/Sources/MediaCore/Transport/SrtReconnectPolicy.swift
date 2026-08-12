import Foundation

/// Reconnect belongs exclusively to the SRT transport layer.
public struct SrtReconnectPolicy: Sendable, Equatable {
    public var initialDelayMs: UInt64
    public var maxDelayMs: UInt64
    public var multiplier: Double

    public static let `default` = SrtReconnectPolicy(
        initialDelayMs: 500,
        maxDelayMs: 10_000,
        multiplier: 2.0
    )

    public init(initialDelayMs: UInt64, maxDelayMs: UInt64, multiplier: Double) {
        self.initialDelayMs = initialDelayMs
        self.maxDelayMs = maxDelayMs
        self.multiplier = multiplier
    }

    public func delay(forAttempt attempt: Int) -> Duration {
        guard attempt > 0 else {
            return .milliseconds(Int64(initialDelayMs))
        }
        var delay = Double(initialDelayMs)
        for _ in 1..<attempt {
            delay *= multiplier
            if delay >= Double(maxDelayMs) {
                return .milliseconds(Int64(maxDelayMs))
            }
        }
        return .milliseconds(Int64(min(UInt64(delay.rounded()), maxDelayMs)))
    }
}

/// Transport-owned reconnect state. Encoder failures are NOT handled here.
public actor SrtTransportSupervisor {
    private let policy: SrtReconnectPolicy
    private(set) var attempt: Int = 0
    private(set) var isReconnecting = false

    public init(policy: SrtReconnectPolicy = .default) {
        self.policy = policy
    }

    public func nextBackoff() -> Duration {
        attempt += 1
        isReconnecting = true
        return policy.delay(forAttempt: attempt)
    }

    public func markConnected() {
        attempt = 0
        isReconnecting = false
    }

    public func reset() {
        attempt = 0
        isReconnecting = false
    }
}
