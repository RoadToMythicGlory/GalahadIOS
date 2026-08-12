import Foundation

public enum MediaCoreError: Error, LocalizedError, Sendable, Equatable {
    case unsupportedPixelFormat(PixelFormat)
    case notConfigured(String)
    case invalidEndpoint(String)
    case transportNotConnected
    case transportUnavailable(String)
    case pluginRegistrationFailed(String)
    case deviceValidationRequired
    case encoderNotViable(String)
    case presetNotAllowed(String)
    case pipelineFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPixelFormat(let format):
            return "Unsupported pixel format: \(format.rawValue)"
        case .notConfigured(let component):
            return "\(component) is not configured"
        case .invalidEndpoint(let url):
            return "Invalid SRT endpoint: \(url)"
        case .transportNotConnected:
            return "SRT transport is not connected"
        case .transportUnavailable(let detail):
            return "GStreamer SRT transport unavailable: \(detail)"
        case .pluginRegistrationFailed(let detail):
            return "GStreamer plugin registration failed: \(detail)"
        case .deviceValidationRequired:
            return "DEVICE VALIDATION REQUIRED"
        case .encoderNotViable(let detail):
            return "HEVC encoder not viable: \(detail)"
        case .presetNotAllowed(let id):
            return "Preset '\(id)' is not startable (unvalidated or lab mode disabled)"
        case .pipelineFailed(let detail):
            return "Pipeline failed: \(detail)"
        }
    }
}
