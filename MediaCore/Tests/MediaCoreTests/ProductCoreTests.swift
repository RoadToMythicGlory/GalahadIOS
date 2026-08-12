import XCTest
@testable import MediaCore

final class ProductCoreTests: XCTestCase {
    func testClientConfigJSONRoundTrip() throws {
        var config = ClientConfig(
            displayName: "Idan",
            destinationHost: "10.0.0.5",
            destinationPort: 9003,
            latencyMs: 400,
            presetId: "1080p60",
            videoSource: .frontCamera
        )
        config.audio.sources[0].muted = true
        let data = try JSONEncoder().encode(config)
        let back = try JSONDecoder().decode(ClientConfig.self, from: data)
        XCTAssertEqual(back.displayName, "Idan")
        XCTAssertEqual(back.destinationPort, 9003)
        XCTAssertEqual(back.latencyMs, 400)
        XCTAssertEqual(back.videoSource, .frontCamera)
        XCTAssertTrue(back.audio.sources[0].muted)
        XCTAssertTrue(String(data: data, encoding: .utf8)!.contains("playerId"))
    }

    func testLatencyFloorOnDecode() throws {
        let json = """
        {"playerId":"player-abc","displayName":"X","destinationHost":"1.1.1.1","destinationPort":9,"latencyMs":50,"presetId":"1080p60","videoSource":"rearCamera","audio":{"sources":[]}}
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(ClientConfig.self, from: json)
        XCTAssertEqual(config.latencyMs, 200)
    }

    func testIdentitySessionUniquePerInit() {
        let config = ClientConfig(playerId: "player-fixed", displayName: "A")
        let a = Identity(config: config)
        let b = Identity(config: config)
        XCTAssertEqual(a.playerId, b.playerId)
        XCTAssertNotEqual(a.sessionId, b.sessionId)
    }

    func testAppGroupStoreInMemoryRoundTrip() async throws {
        let store = AppGroupStore(suiteName: "group.gg.galahad.ios.tests.\(UUID().uuidString)")
        let config = ClientConfig(displayName: "RoundTrip", destinationHost: "127.0.0.1", destinationPort: 9001)
        try await store.saveConfig(config)
        let loaded = await store.loadConfig()
        XCTAssertEqual(loaded.displayName, "RoundTrip")
        XCTAssertEqual(loaded.destinationPort, 9001)

        let status = StreamStatus(state: .streaming, fps: 59.9, bitrateMbps: 12)
        try await store.saveStatus(status)
        let loadedStatus = await store.loadStatus()
        XCTAssertEqual(loadedStatus.state, .streaming)
        XCTAssertEqual(loadedStatus.fps, 59.9, accuracy: 0.01)
    }

    func testPresetGatingBlocksProductionWithoutValidation() async throws {
        let caps = CapabilityStore(labStubModeEnabled: false)
        await caps.setGStreamerSrtAvailable(true)
        await caps.setValidatedPresetIds([])
        let production = await caps.selectablePresets(productionOnly: true)
        XCTAssertTrue(production.isEmpty)
        do {
            try await caps.assertStartAllowed(presetId: "1080p60", preferProduction: true)
            XCTFail("expected presetNotAllowed")
        } catch let error as MediaCoreError {
            guard case .presetNotAllowed = error else {
                return XCTFail("wrong error \(error)")
            }
        }
    }

    func testLabStubModeAllowsUnvalidatedPresets() async throws {
        let caps = CapabilityStore(labStubModeEnabled: true)
        await caps.setValidatedPresetIds([])
        let selectable = await caps.selectablePresets(productionOnly: false)
        XCTAssertFalse(selectable.isEmpty)
        XCTAssertFalse(selectable[0].isProductionStartable)
        try await caps.assertStartAllowed(presetId: "720p30", preferProduction: false)
    }

    func testStreamCoordinatorStartStopStateMachine() async throws {
        let coordinator = StreamCoordinator()
        let profile = VideoProfile.gateCandidates[0]
        let transport = RecordingSrtTransport(
            endpoint: SrtEndpoint(host: "127.0.0.1", port: 9001)
        )
        try await coordinator.start(
            profile: profile,
            encoder: StubHEVCEncoder(),
            normalizer: PassthroughFrameNormalizer(format: .i420),
            muxer: FileMpegTsMuxer(),
            transport: transport
        )
        var status = await coordinator.status
        XCTAssertEqual(status.state, .streaming)

        let frame = TestPatternGenerator(profile: profile).frame(index: 0)
        try await coordinator.submitRawFrame(
            raw: frame,
            width: profile.width,
            height: profile.height,
            inputFormat: .i420,
            presentationTime: .milliseconds(0)
        )
        status = await coordinator.status
        XCTAssertEqual(status.state, .streaming)
        XCTAssertGreaterThan(status.fps, 0)

        await coordinator.stop()
        status = await coordinator.status
        XCTAssertEqual(status.state, .idle)
    }

    func testStreamCoordinatorFatalWithoutFactoryFails() async throws {
        let coordinator = StreamCoordinator()
        let profile = VideoProfile.gateCandidates[0]
        let transport = RecordingSrtTransport(
            endpoint: SrtEndpoint(host: "127.0.0.1", port: 9001)
        )
        let encoder = FailingEncoder()
        try await coordinator.start(
            profile: profile,
            encoder: encoder,
            normalizer: PassthroughFrameNormalizer(format: .i420),
            muxer: FileMpegTsMuxer(),
            transport: transport
        )
        await encoder.setFailNextEncode(true)
        let frame = TestPatternGenerator(profile: profile).frame(index: 0)
        do {
            try await coordinator.submitRawFrame(
                raw: frame,
                width: profile.width,
                height: profile.height,
                inputFormat: .i420,
                presentationTime: .zero
            )
            XCTFail("expected failure")
        } catch {
            let status = await coordinator.status
            XCTAssertEqual(status.state, .failed)
        }
    }

    func testControlCommandParseAndAckSerialize() throws {
        let restart = try ServerControlCommand.parse(#"{"action":"restart_stream"}"#)
        XCTAssertEqual(restart, .restartStream)
        XCTAssertEqual(restart.actionName, "restart_stream")

        let quality = try ServerControlCommand.parse(#"{"action":"switch_quality","preset":"720p30"}"#)
        XCTAssertEqual(quality, .switchQuality(preset: "720p30"))

        let push = try ServerControlCommand.parse(
            #"{"action":"push_config","config":{"playerId":"player-x","displayName":"N","destinationHost":"1.2.3.4","destinationPort":9003,"latencyMs":200,"presetId":"1080p60","videoSource":"screen","audio":{"sources":[]}}}"#
        )
        guard case let .pushConfig(config) = push else {
            return XCTFail("expected push_config")
        }
        XCTAssertEqual(config.videoSource, .screen)
        XCTAssertEqual(config.presetId, "1080p60")

        XCTAssertThrowsError(try ServerControlCommand.parse(#"{"action":"explode"}"#))

        let ack = CommandAck(action: "start_stream", ok: false, detail: CommandAck.userActionRequired)
        let data = try ClientControlMessage.commandAck(ack).jsonData()
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains("command_ack"))
        XCTAssertTrue(text.contains("user_action_required"))
    }

    func testQualityPresetCatalogIsMobileHEVCRange() {
        let ids = QualityPreset.catalog.map(\.id)
        XCTAssertEqual(ids, ["720p30", "1080p30", "1080p50", "1080p60"])
        for preset in QualityPreset.catalog {
            XCTAssertGreaterThan(preset.hevcKbps, 0)
            XCTAssertGreaterThanOrEqual(preset.width, 1280)
            XCTAssertLessThan(preset.width, 3840)
        }
        XCTAssertEqual(QualityPreset.resolveOrDefault(id: "1080p60").hevcKbps, 8400)
    }

    func testEncoderFactoryConfiguresStubForPreset() async throws {
        let factory = EncoderFactory.stub
        let preset = QualityPreset.resolveOrDefault(id: "720p30")
        let encoder = try await factory.makeConfigured(for: preset, inputFormat: .i420)
        XCTAssertEqual(encoder.name, "stub-hevc")
    }
}

/// Encoder that can fail on demand for coordinator failure tests.
private actor FailingEncoder: VideoEncoder {
    let name = "failing-stub"
    let supportedInputFormats: [PixelFormat] = [.i420]
    private var failNext = false
    private var configured = false

    func setFailNextEncode(_ value: Bool) { failNext = value }

    func configure(profile: VideoProfile, inputFormat: PixelFormat, targetKbps: UInt32?) async throws {
        _ = profile; _ = inputFormat; _ = targetKbps
        configured = true
    }

    func encode(_ frame: NormalizedFrame) async throws -> EncodedAccessUnit? {
        _ = frame
        if failNext {
            throw MediaCoreError.encoderNotViable("forced")
        }
        guard configured else { throw MediaCoreError.notConfigured("FailingEncoder") }
        let now = ContinuousClock.now
        return EncodedAccessUnit(
            data: Data("X".utf8),
            presentationTime: .zero,
            encodeStarted: now,
            encodeFinished: now,
            width: 1,
            height: 1
        )
    }

    func flush() async throws -> [EncodedAccessUnit] { [] }
    func teardown() async { configured = false }
}
