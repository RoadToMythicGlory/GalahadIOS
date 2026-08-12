import XCTest
@testable import MediaCore

final class PipelineLayerTests: XCTestCase {
    func testLayeredPipelineEmitsTSAndVerifiesPacketization() async throws {
        let profile = VideoProfile.gateCandidates[0]
        let generator = TestPatternGenerator(profile: profile)
        let coordinator = FeasibilityPipelineCoordinator()
        let encoder = StubHEVCEncoder()
        let normalizer = PassthroughFrameNormalizer(format: .i420)
        // Product muxer: real MPEG-TS with 1316-aligned output, so the
        // packetization verifier sees preferred 7×188 payloads.
        let muxer = MpegTsStreamMuxer()
        let transport = RecordingSrtTransport(
            endpoint: SrtEndpoint(host: "127.0.0.1", port: 9001)
        )

        try await coordinator.start(
            profile: profile,
            encoder: encoder,
            normalizer: normalizer,
            muxer: muxer,
            transport: transport
        )

        for i in 0..<45 {
            let frame = generator.frame(index: UInt64(i))
            try await coordinator.submitRawFrame(
                raw: frame,
                width: profile.width,
                height: profile.height,
                inputFormat: .i420,
                presentationTime: .milliseconds(Int64(i * 1000 / profile.frameRate))
            )
        }

        let metrics = await coordinator.snapshotMetrics()
        XCTAssertEqual(metrics.framesEncoded, 45)
        XCTAssertGreaterThan(metrics.bytesEmitted, 0)

        let sizes = await transport.observedPayloadSizes()
        let report = DefaultPacketizationVerifier().verify(observedPayloadSizes: sizes)
        XCTAssertTrue(report.matchesPreferred, report.notes)

        await coordinator.stop()
        let status = await coordinator.status
        XCTAssertEqual(status.state, .idle)
    }

    func testTransportOwnsReconnectAttempts() async throws {
        let transport = RecordingSrtTransport(
            endpoint: SrtEndpoint(host: "127.0.0.1", port: 9001)
        )
        try await transport.connect()
        let d1 = await transport.simulateDisconnectAndBackoff()
        XCTAssertEqual(d1, .milliseconds(500))
        let d2 = await transport.simulateDisconnectAndBackoff()
        XCTAssertEqual(d2, .milliseconds(1000))
    }
}
