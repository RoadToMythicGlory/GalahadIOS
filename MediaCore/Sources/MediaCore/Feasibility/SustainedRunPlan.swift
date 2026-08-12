import Foundation

/// Describes how a physical-device sustained run must be executed.
/// The harness records evidence; it never fabricates pass/fail metrics.
public struct SustainedRunPlan: Codable, Sendable, Equatable {
    public var profile: VideoProfile
    public var criteria: SustainedRunCriteria
    public var srtEndpoint: SrtEndpoint
    public var outputTsFileName: String

    public init(
        profile: VideoProfile,
        criteria: SustainedRunCriteria = .planDefault,
        srtEndpoint: SrtEndpoint,
        outputTsFileName: String? = nil
    ) {
        self.profile = profile
        self.criteria = criteria
        self.srtEndpoint = srtEndpoint
        self.outputTsFileName = outputTsFileName ?? "\(profile.id).ts"
    }

    public static func gatePlans(receiverHost: String, basePort: UInt16 = 9001) -> [SustainedRunPlan] {
        VideoProfile.gateCandidates.enumerated().map { index, profile in
            SustainedRunPlan(
                profile: profile,
                srtEndpoint: SrtEndpoint(
                    host: receiverHost,
                    port: basePort + UInt16(index),
                    latencyMs: SrtEndpoint.minimumLatencyMs
                )
            )
        }
    }

    public var expectedFramesAfterWarmup: UInt64 {
        let total = UInt64(profile.frameRate) * UInt64(criteria.minimumDurationSeconds.rounded())
        let warmup = UInt64(profile.frameRate * 2)
        return total > warmup ? total - warmup : 0
    }
}
