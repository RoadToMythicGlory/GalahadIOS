import XCTest
@testable import MediaCore

final class SrtAndReconnectTests: XCTestCase {
    func testCallerURLEnforcesLatencyFloorAndPreferredPktSize() {
        let endpoint = SrtEndpoint(host: "10.0.0.5", port: 9003, latencyMs: 120)
        XCTAssertEqual(endpoint.latencyMs, 200)
        XCTAssertTrue(endpoint.callerURL.contains("mode=caller"))
        XCTAssertTrue(endpoint.callerURL.contains("latency=200"))
        XCTAssertTrue(endpoint.callerURL.contains("pkt_size=1316"))
    }

    func testReconnectBackoffCapsAtTenSeconds() {
        let policy = SrtReconnectPolicy.default
        XCTAssertEqual(policy.delay(forAttempt: 1), .milliseconds(500))
        XCTAssertEqual(policy.delay(forAttempt: 2), .milliseconds(1000))
        XCTAssertEqual(policy.delay(forAttempt: 3), .milliseconds(2000))
        XCTAssertEqual(policy.delay(forAttempt: 20), .milliseconds(10_000))
    }

    func testPacketizationVerifierRequiresObservedPackets() {
        let verifier = DefaultPacketizationVerifier()
        let empty = verifier.verify(observedPayloadSizes: [])
        XCTAssertFalse(empty.matchesPreferred)

        let good = verifier.verify(observedPayloadSizes: Array(repeating: 1316, count: 100))
        XCTAssertTrue(good.matchesPreferred)

        let bad = verifier.verify(observedPayloadSizes: Array(repeating: 1200, count: 100))
        XCTAssertFalse(bad.matchesPreferred)
    }
}
