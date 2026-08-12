import Foundation

public enum StreamLifecycle: String, Codable, Sendable {
    case idle
    case starting
    case streaming
    case degraded
    case reconnecting
    case failed
}

public struct StreamStatus: Codable, Sendable, Equatable {
    public var state: StreamLifecycle
    public var fps: Double
    public var bitrateMbps: Double
    public var droppedFrames: UInt64
    public var encoderName: String?
    public var captureBackend: String?
    public var lastError: String?
    public var workingMemoryBytes: UInt64
    public var cpuPercent: Double
    public var thermalState: ThermalPressure

    public init(
        state: StreamLifecycle = .idle,
        fps: Double = 0,
        bitrateMbps: Double = 0,
        droppedFrames: UInt64 = 0,
        encoderName: String? = nil,
        captureBackend: String? = nil,
        lastError: String? = nil,
        workingMemoryBytes: UInt64 = 0,
        cpuPercent: Double = 0,
        thermalState: ThermalPressure = .nominal
    ) {
        self.state = state
        self.fps = fps
        self.bitrateMbps = bitrateMbps
        self.droppedFrames = droppedFrames
        self.encoderName = encoderName
        self.captureBackend = captureBackend
        self.lastError = lastError
        self.workingMemoryBytes = workingMemoryBytes
        self.cpuPercent = cpuPercent
        self.thermalState = thermalState
    }
}

public enum ThermalPressure: String, Codable, Sendable {
    case nominal
    case fair
    case serious
    case critical
}
