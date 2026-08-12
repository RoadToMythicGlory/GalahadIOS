import Foundation

/// Capture → Frame normalization boundary.
public protocol FrameNormalizer: AnyObject, Sendable {
    var supportedInputFormats: [PixelFormat] { get }
    var outputFormat: PixelFormat { get }

    func prepare(profile: VideoProfile) async throws
    func normalize(
        raw: Data,
        width: Int,
        height: Int,
        inputFormat: PixelFormat,
        presentationTime: Duration,
        captureTimestamp: ContinuousClock.Instant
    ) async throws -> NormalizedFrame
    func teardown() async
}

/// Video encoder abstraction (product path: H.265 / HEVC).
/// MediaCore never calls VideoToolbox or GStreamer encode APIs directly.
public protocol VideoEncoder: AnyObject, Sendable {
    var name: String { get }
    var supportedInputFormats: [PixelFormat] { get }

    func configure(profile: VideoProfile, inputFormat: PixelFormat, targetKbps: UInt32?) async throws
    /// Returns nil when the encoder legitimately dropped the frame (e.g. under
    /// real-time pressure); callers count it as dropped, not as a failure.
    func encode(_ frame: NormalizedFrame) async throws -> EncodedAccessUnit?
    func flush() async throws -> [EncodedAccessUnit]
    func teardown() async
}

/// MPEG-TS mux layer.
public protocol MpegTsMuxer: AnyObject, Sendable {
    func configure(profile: VideoProfile, includeAudio: Bool) async throws
    func pushVideo(_ unit: EncodedAccessUnit) async throws -> Data?
    func pushAudioAAC(_ packet: Data, presentationTime: Duration) async throws -> Data?
    func finalize() async throws -> Data
    func teardown() async
}

/// SRT caller transport. Reconnect lives here exclusively.
/// State properties are `get async` so actor implementations (the product
/// transport is an actor) can witness them from their isolated storage.
public protocol SrtCallerTransport: AnyObject, Sendable {
    var endpoint: SrtEndpoint { get }
    var isConnected: Bool { get async }
    /// Transport-owned reconnect flag; coordinators observe but never drive backoff.
    var isReconnecting: Bool { get async }

    func connect() async throws
    func send(mpegTsChunk: Data) async throws
    func disconnect() async
    /// Observed emitted UDP/SRT payload sizes. Must not be inferred from config alone.
    func observedPayloadSizes() async -> [Int]
}

public protocol PacketizationVerifier: Sendable {
    /// Returns true when observed payloads match the preferred 1316-byte TS packing
    /// (7 × 188) or an explicitly documented supported alternative.
    func verify(observedPayloadSizes: [Int], preferred: Int) -> PacketizationReport
}

public struct PacketizationReport: Codable, Sendable, Equatable {
    public var preferredBytes: Int
    public var observedSizes: [Int]
    public var dominantSize: Int?
    public var matchesPreferred: Bool
    public var notes: String

    public init(
        preferredBytes: Int,
        observedSizes: [Int],
        dominantSize: Int?,
        matchesPreferred: Bool,
        notes: String
    ) {
        self.preferredBytes = preferredBytes
        self.observedSizes = observedSizes
        self.dominantSize = dominantSize
        self.matchesPreferred = matchesPreferred
        self.notes = notes
    }
}

/// Top-level coordinator. Must not become a GStreamer God Object.
public protocol PipelineCoordinator: AnyObject, Sendable {
    var status: StreamStatus { get async }

    func start(
        profile: VideoProfile,
        encoder: VideoEncoder,
        normalizer: FrameNormalizer,
        muxer: MpegTsMuxer,
        transport: SrtCallerTransport
    ) async throws

    func stop() async
}
