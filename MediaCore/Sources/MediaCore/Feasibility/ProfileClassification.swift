import Foundation

public enum ProfileClassification: String, Codable, Sendable {
    case supported = "SUPPORTED"
    case unsupported = "UNSUPPORTED"
    case deviceSpecific = "DEVICE-SPECIFIC"
    case inconclusive = "INCONCLUSIVE"
    case notTested = "NOT TESTED"
}

public struct SustainedRunCriteria: Codable, Sendable, Equatable {
    /// Minimum continuous run duration in seconds (plan: 30 minutes).
    public var minimumDurationSeconds: Double
    /// Fraction of expected real-time frames after warm-up (plan: 0.99).
    public var minimumFrameDeliveryRatio: Double
    /// Max allowed working-memory growth vs post-warm-up baseline (plan: 0.10).
    public var maxMemoryGrowthRatio: Double
    public var allowCriticalThermal: Bool

    public static let planDefault = SustainedRunCriteria(
        minimumDurationSeconds: 30 * 60,
        minimumFrameDeliveryRatio: 0.99,
        maxMemoryGrowthRatio: 0.10,
        allowCriticalThermal: false
    )

    public init(
        minimumDurationSeconds: Double,
        minimumFrameDeliveryRatio: Double,
        maxMemoryGrowthRatio: Double,
        allowCriticalThermal: Bool
    ) {
        self.minimumDurationSeconds = minimumDurationSeconds
        self.minimumFrameDeliveryRatio = minimumFrameDeliveryRatio
        self.maxMemoryGrowthRatio = maxMemoryGrowthRatio
        self.allowCriticalThermal = allowCriticalThermal
    }
}

public struct ProfileRunEvidence: Codable, Sendable, Equatable {
    public var profileID: String
    public var deviceModel: String
    public var classification: ProfileClassification
    public var durationSeconds: Double
    public var expectedFramesAfterWarmup: UInt64
    public var deliveredFramesAfterWarmup: UInt64
    public var frameDeliveryRatio: Double
    public var measuredFps: Double
    public var cpuPercentAverage: Double
    public var memoryBytesBaseline: UInt64
    public var memoryBytesEnd: UInt64
    public var memoryGrowthRatio: Double
    public var peakThermal: ThermalPressure
    public var bitrateMbps: Double
    public var encoderLatencyMs: Double
    public var endToEndLatencyMs: Double
    public var mpegTsDecodable: Bool
    public var srtDelivered: Bool
    public var packetizationVerified: Bool
    public var notes: String

    public init(
        profileID: String,
        deviceModel: String,
        classification: ProfileClassification,
        durationSeconds: Double = 0,
        expectedFramesAfterWarmup: UInt64 = 0,
        deliveredFramesAfterWarmup: UInt64 = 0,
        frameDeliveryRatio: Double = 0,
        measuredFps: Double = 0,
        cpuPercentAverage: Double = 0,
        memoryBytesBaseline: UInt64 = 0,
        memoryBytesEnd: UInt64 = 0,
        memoryGrowthRatio: Double = 0,
        peakThermal: ThermalPressure = .nominal,
        bitrateMbps: Double = 0,
        encoderLatencyMs: Double = 0,
        endToEndLatencyMs: Double = 0,
        mpegTsDecodable: Bool = false,
        srtDelivered: Bool = false,
        packetizationVerified: Bool = false,
        notes: String = ""
    ) {
        self.profileID = profileID
        self.deviceModel = deviceModel
        self.classification = classification
        self.durationSeconds = durationSeconds
        self.expectedFramesAfterWarmup = expectedFramesAfterWarmup
        self.deliveredFramesAfterWarmup = deliveredFramesAfterWarmup
        self.frameDeliveryRatio = frameDeliveryRatio
        self.measuredFps = measuredFps
        self.cpuPercentAverage = cpuPercentAverage
        self.memoryBytesBaseline = memoryBytesBaseline
        self.memoryBytesEnd = memoryBytesEnd
        self.memoryGrowthRatio = memoryGrowthRatio
        self.peakThermal = peakThermal
        self.bitrateMbps = bitrateMbps
        self.encoderLatencyMs = encoderLatencyMs
        self.endToEndLatencyMs = endToEndLatencyMs
        self.mpegTsDecodable = mpegTsDecodable
        self.srtDelivered = srtDelivered
        self.packetizationVerified = packetizationVerified
        self.notes = notes
    }
}

public struct GateClassifier: Sendable {
    public var criteria: SustainedRunCriteria

    public init(criteria: SustainedRunCriteria = .planDefault) {
        self.criteria = criteria
    }

    public func classify(
        profileID: String,
        deviceModel: String,
        durationSeconds: Double,
        expectedFramesAfterWarmup: UInt64,
        deliveredFramesAfterWarmup: UInt64,
        memoryBytesBaseline: UInt64,
        memoryBytesEnd: UInt64,
        peakThermal: ThermalPressure,
        mpegTsDecodable: Bool,
        srtDelivered: Bool,
        packetizationVerified: Bool,
        measuredFps: Double,
        cpuPercentAverage: Double,
        bitrateMbps: Double,
        encoderLatencyMs: Double,
        endToEndLatencyMs: Double,
        progressiveFrameLoss: Bool,
        crashedOrOOM: Bool,
        notes: String = ""
    ) -> ProfileRunEvidence {
        let ratio: Double
        if expectedFramesAfterWarmup == 0 {
            ratio = 0
        } else {
            ratio = Double(deliveredFramesAfterWarmup) / Double(expectedFramesAfterWarmup)
        }
        let growth: Double
        if memoryBytesBaseline == 0 {
            growth = memoryBytesEnd == 0 ? 0 : 1
        } else {
            growth = Double(memoryBytesEnd) / Double(memoryBytesBaseline) - 1.0
        }

        let incomplete = durationSeconds < criteria.minimumDurationSeconds
            || !mpegTsDecodable
            || !srtDelivered

        let thermalFail = peakThermal == .critical && !criteria.allowCriticalThermal
        let thermalSoftFail = peakThermal == .serious && ratio < criteria.minimumFrameDeliveryRatio
        let memoryFail = growth > criteria.maxMemoryGrowthRatio
        let realtimeFail = ratio < criteria.minimumFrameDeliveryRatio || progressiveFrameLoss

        let classification: ProfileClassification
        if crashedOrOOM {
            classification = .unsupported
        } else if incomplete {
            classification = .inconclusive
        } else if realtimeFail || memoryFail || thermalFail || thermalSoftFail || !packetizationVerified {
            classification = .unsupported
        } else {
            classification = .supported
        }

        return ProfileRunEvidence(
            profileID: profileID,
            deviceModel: deviceModel,
            classification: classification,
            durationSeconds: durationSeconds,
            expectedFramesAfterWarmup: expectedFramesAfterWarmup,
            deliveredFramesAfterWarmup: deliveredFramesAfterWarmup,
            frameDeliveryRatio: ratio,
            measuredFps: measuredFps,
            cpuPercentAverage: cpuPercentAverage,
            memoryBytesBaseline: memoryBytesBaseline,
            memoryBytesEnd: memoryBytesEnd,
            memoryGrowthRatio: growth,
            peakThermal: peakThermal,
            bitrateMbps: bitrateMbps,
            encoderLatencyMs: encoderLatencyMs,
            endToEndLatencyMs: endToEndLatencyMs,
            mpegTsDecodable: mpegTsDecodable,
            srtDelivered: srtDelivered,
            packetizationVerified: packetizationVerified,
            notes: notes
        )
    }

    /// GO requires ≥1 useful profile (≥720p30) classified SUPPORTED.
    public func evaluateGate(results: [ProfileRunEvidence]) -> GateDecision {
        let useful = results.filter { result in
            guard result.classification == .supported else { return false }
            guard let profile = VideoProfile.gateCandidates.first(where: { $0.id == result.profileID }) else {
                return false
            }
            // Practically useful: 720p30 or higher resolution/fps product.
            return profile.width >= 1280 && profile.height >= 720 && profile.frameRate >= 30
        }

        if useful.isEmpty {
            let hasDeviceSpecific = results.contains { $0.classification == .deviceSpecific }
            if hasDeviceSpecific {
                return GateDecision(
                    verdict: .noGo,
                    reason: "Only DEVICE-SPECIFIC results present; propose an explicit device allow-list before GO.",
                    viableProfiles: results.filter { $0.classification == .deviceSpecific }.map(\.profileID)
                )
            }
            if results.allSatisfy({ $0.classification == .inconclusive || $0.classification == .notTested }) {
                return GateDecision(
                    verdict: .deviceValidationRequired,
                    reason: "DEVICE VALIDATION REQUIRED",
                    viableProfiles: []
                )
            }
            return GateDecision(
                verdict: .noGo,
                reason: "No SUPPORTED profile at 720p30 or higher.",
                viableProfiles: []
            )
        }

        return GateDecision(
            verdict: .go,
            reason: "At least one useful profile is SUPPORTED.",
            viableProfiles: useful.map(\.profileID)
        )
    }
}

public enum GateVerdict: String, Codable, Sendable {
    case go = "GO"
    case noGo = "NO-GO"
    case deviceValidationRequired = "DEVICE VALIDATION REQUIRED"
}

public struct GateDecision: Codable, Sendable, Equatable {
    public var verdict: GateVerdict
    public var reason: String
    public var viableProfiles: [String]

    public init(verdict: GateVerdict, reason: String, viableProfiles: [String]) {
        self.verdict = verdict
        self.reason = reason
        self.viableProfiles = viableProfiles
    }
}
