import Foundation

/// iOS capture source selection (not Windows window/device).
public enum VideoSource: String, Codable, Sendable, CaseIterable, Equatable {
    case frontCamera
    case rearCamera
    case screen

    public var captureBackendLabel: String {
        switch self {
        case .frontCamera: return "avfoundation-front"
        case .rearCamera: return "avfoundation-rear"
        case .screen: return "replaykit-broadcast"
        }
    }

    public var requiresSystemBroadcastPicker: Bool {
        self == .screen
    }
}
