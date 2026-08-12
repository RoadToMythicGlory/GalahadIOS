import Foundation

/// Non-production encoder stub for unit tests and Windows scaffolding.
/// Product builds use `VideoToolboxHEVCEncoder` on device.
public actor StubHEVCEncoder: VideoEncoder {
    public let name = "stub-hevc"
    public let supportedInputFormats: [PixelFormat] = [.i420, .bgra]

    private var configured = false
    private var profile: VideoProfile?

    public init() {}

    public func configure(profile: VideoProfile, inputFormat: PixelFormat, targetKbps: UInt32?) async throws {
        guard supportedInputFormats.contains(inputFormat) else {
            throw MediaCoreError.unsupportedPixelFormat(inputFormat)
        }
        self.profile = profile
        self.configured = true
        _ = targetKbps
    }

    public func encode(_ frame: NormalizedFrame) async throws -> EncodedAccessUnit? {
        guard configured else { throw MediaCoreError.notConfigured("VideoEncoder") }
        let started = ContinuousClock.now
        // Deterministic fake Annex-B-ish payload for harness wiring tests only.
        var payload = Data([0x00, 0x00, 0x00, 0x01, 0x40]) // fake VPS start
        payload.append(contentsOf: withUnsafeBytes(of: UInt32(frame.width).bigEndian) { Data($0) })
        payload.append(contentsOf: withUnsafeBytes(of: UInt32(frame.height).bigEndian) { Data($0) })
        payload.append(frame.pixelBuffer.prefix(64))
        let finished = ContinuousClock.now
        return EncodedAccessUnit(
            data: payload,
            presentationTime: frame.presentationTime,
            encodeStarted: started,
            encodeFinished: finished,
            width: frame.width,
            height: frame.height
        )
    }

    public func flush() async throws -> [EncodedAccessUnit] { [] }

    public func teardown() async {
        configured = false
        profile = nil
    }
}
