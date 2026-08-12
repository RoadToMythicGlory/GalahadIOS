import XCTest
@testable import MediaCore

final class GateClassifierTests: XCTestCase {
    func testSupportedProfileCanProduceGOWithout1080p60() {
        let classifier = GateClassifier()
        let p720 = makePassing(profileID: "720p30")
        let p1080_30 = makePassing(profileID: "1080p30")
        let p1080_60 = ProfileRunEvidence(
            profileID: "1080p60",
            deviceModel: "iPhone16,2",
            classification: .unsupported,
            durationSeconds: 1800,
            notes: "Thermal throttling"
        )

        let decision = classifier.evaluateGate(results: [p720, p1080_30, p1080_60])
        XCTAssertEqual(decision.verdict, .go)
        XCTAssertTrue(decision.viableProfiles.contains("720p30"))
        XCTAssertFalse(decision.viableProfiles.contains("1080p60"))
    }

    func testScaffoldReportIsDeviceValidationRequired() throws {
        let report = DeviceValidationReportBuilder.buildScaffoldHostReport()
        XCTAssertEqual(report.decision.verdict, .deviceValidationRequired)
        XCTAssertTrue(report.decision.reason.contains("DEVICE VALIDATION REQUIRED"))
        XCTAssertFalse(report.pluginRegistration.gstInitSucceeded)
        let json = try report.jsonString()
        XCTAssertTrue(json.contains("DEVICE VALIDATION REQUIRED"))
    }

    func testClassifyIncompleteRunAsInconclusive() {
        let classifier = GateClassifier()
        let evidence = classifier.classify(
            profileID: "720p30",
            deviceModel: "iPhone16,2",
            durationSeconds: 60,
            expectedFramesAfterWarmup: 1800,
            deliveredFramesAfterWarmup: 1800,
            memoryBytesBaseline: 100,
            memoryBytesEnd: 100,
            peakThermal: .nominal,
            mpegTsDecodable: true,
            srtDelivered: true,
            packetizationVerified: true,
            measuredFps: 30,
            cpuPercentAverage: 40,
            bitrateMbps: 80,
            encoderLatencyMs: 8,
            endToEndLatencyMs: 40,
            progressiveFrameLoss: false,
            crashedOrOOM: false
        )
        XCTAssertEqual(evidence.classification, .inconclusive)
    }

    private func makePassing(profileID: String) -> ProfileRunEvidence {
        ProfileRunEvidence(
            profileID: profileID,
            deviceModel: "iPhone16,2",
            classification: .supported,
            durationSeconds: 1800,
            expectedFramesAfterWarmup: 50_000,
            deliveredFramesAfterWarmup: 49_800,
            frameDeliveryRatio: 0.996,
            measuredFps: 30,
            cpuPercentAverage: 55,
            memoryBytesBaseline: 200_000_000,
            memoryBytesEnd: 205_000_000,
            memoryGrowthRatio: 0.025,
            peakThermal: .fair,
            bitrateMbps: 90,
            encoderLatencyMs: 10,
            endToEndLatencyMs: 55,
            mpegTsDecodable: true,
            srtDelivered: true,
            packetizationVerified: true,
            notes: "fixture"
        )
    }
}
