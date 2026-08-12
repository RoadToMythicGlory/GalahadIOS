import CoreMedia
import CoreVideo
import Foundation
import MediaCore
import VideoToolbox

/// Product H.265 encoder backed by hardware VideoToolbox (`VTCompressionSession`).
/// Used by the host app and broadcast extension. Mux is MediaCore's
/// `MpegTsStreamMuxer`; SRT egress is the GStreamer bridge.
public actor VideoToolboxHEVCEncoder: VideoEncoder {
    public let name = "videotoolbox-hevc"
    public let supportedInputFormats: [PixelFormat] = [.bgra, .nv12, .i420]

    private var session: VTCompressionSession?
    private var profile: VideoProfile?
    private var inputFormat: PixelFormat = .nv12
    private var targetKbps: UInt32 = 2500

    public init() {}

    /// True when the device can create a real-time HEVC compression session.
    public static func isAvailable() -> Bool {
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: 1280,
            height: 720,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        if let session {
            VTCompressionSessionInvalidate(session)
        }
        return status == noErr
    }

    public func configure(profile: VideoProfile, inputFormat: PixelFormat, targetKbps: UInt32?) async throws {
        guard supportedInputFormats.contains(inputFormat) else {
            throw MediaCoreError.unsupportedPixelFormat(inputFormat)
        }
        guard profile.scan == .progressive else {
            // VideoToolbox HEVC does not produce true interlaced output.
            throw MediaCoreError.encoderNotViable("interlaced profiles are not supported by VideoToolbox HEVC")
        }
        await teardown()
        self.profile = profile
        self.inputFormat = inputFormat
        self.targetKbps = targetKbps ?? profile.targetKbps ?? 2500

        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(profile.width),
            height: Int32(profile.height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard status == noErr, let session else {
            throw MediaCoreError.encoderNotViable("VTCompressionSessionCreate failed: \(status)")
        }

        let bitrate = Int(self.targetKbps) * 1000
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
        // Cap instantaneous rate at ~1.5× average per second (bytes per 1 s window).
        let dataRateLimits: [Any] = [bitrate * 3 / 16, 1]
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: dataRateLimits as CFArray)
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ExpectedFrameRate,
            value: profile.frameRate as CFNumber
        )
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
            value: max(profile.frameRate, 1) as CFNumber
        )
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
            value: 1 as CFNumber
        )
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_AllowFrameReordering,
            value: kCFBooleanFalse
        )

        let prepare = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepare == noErr else {
            VTCompressionSessionInvalidate(session)
            throw MediaCoreError.encoderNotViable("PrepareToEncodeFrames failed: \(prepare)")
        }
        self.session = session
    }

    public func encode(_ frame: NormalizedFrame) async throws -> EncodedAccessUnit? {
        guard let session else {
            throw MediaCoreError.notConfigured("VideoToolboxHEVCEncoder")
        }

        let pixelBuffer: CVPixelBuffer
        switch frame.payload {
        case .imageBuffer(let buffer):
            pixelBuffer = buffer // zero-copy: capture buffer straight into VideoToolbox
        case .bytes:
            pixelBuffer = try makePixelBuffer(from: frame)
        }

        let started = ContinuousClock.now
        let pts = Self.cmTime(from: frame.presentationTime)
        let frameRate = profile.map { max($0.frameRate, 1) } ?? 30
        let duration = CMTime(value: 1, timescale: CMTimeScale(frameRate))

        guard let sample = try await encodeFrame(
            session: session,
            pixelBuffer: pixelBuffer,
            pts: pts,
            duration: duration
        ) else {
            return nil // VideoToolbox dropped the frame under real-time pressure
        }

        let annexB = try Self.annexBData(from: sample)
        let finished = ContinuousClock.now
        return EncodedAccessUnit(
            data: annexB,
            presentationTime: frame.presentationTime,
            encodeStarted: started,
            encodeFinished: finished,
            width: frame.width,
            height: frame.height
        )
    }

    public func flush() async throws -> [EncodedAccessUnit] {
        guard let session else { return [] }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        return []
    }

    public func teardown() async {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
        session = nil
        profile = nil
    }

    // MARK: - Private

    /// Resumes a checked continuation at most once, even if VideoToolbox both
    /// returns an error from the submit call and later invokes the handler.
    private final class OneShotResume<T: Sendable>: @unchecked Sendable {
        private var continuation: CheckedContinuation<T, Error>?
        private let lock = NSLock()

        init(_ continuation: CheckedContinuation<T, Error>) {
            self.continuation = continuation
        }

        func resume(returning value: T) {
            take()?.resume(returning: value)
        }

        func resume(throwing error: Error) {
            take()?.resume(throwing: error)
        }

        private func take() -> CheckedContinuation<T, Error>? {
            lock.lock()
            defer { lock.unlock() }
            let taken = continuation
            continuation = nil
            return taken
        }
    }

    /// Returns nil when the encoder dropped the frame (legal under RealTime mode).
    private func encodeFrame(
        session: VTCompressionSession,
        pixelBuffer: CVPixelBuffer,
        pts: CMTime,
        duration: CMTime
    ) async throws -> CMSampleBuffer? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CMSampleBuffer?, Error>) in
            let resume = OneShotResume<CMSampleBuffer?>(continuation)
            var flags: VTEncodeInfoFlags = []
            let status = VTCompressionSessionEncodeFrame(
                session,
                imageBuffer: pixelBuffer,
                presentationTimeStamp: pts,
                duration: duration,
                frameProperties: nil,
                infoFlagsOut: &flags
            ) { status, infoFlags, sampleBuffer in
                if status == noErr, let sampleBuffer {
                    resume.resume(returning: sampleBuffer)
                } else if status == noErr, infoFlags.contains(.frameDropped) || sampleBuffer == nil {
                    resume.resume(returning: nil)
                } else {
                    resume.resume(
                        throwing: MediaCoreError.encoderNotViable("VT encode failed: \(status)")
                    )
                }
            }
            if status != noErr {
                resume.resume(
                    throwing: MediaCoreError.encoderNotViable("VTCompressionSessionEncodeFrame: \(status)")
                )
            } else if flags.contains(.frameDropped) {
                resume.resume(returning: nil)
            }
        }
    }

    static func cmTime(from duration: Duration) -> CMTime {
        let c = duration.components
        let nanoseconds = c.seconds * 1_000_000_000 + c.attoseconds / 1_000_000_000
        return CMTime(value: nanoseconds, timescale: 1_000_000_000)
    }

    /// Fallback for byte payloads (harness/tests); the product path passes
    /// hardware `CVPixelBuffer`s through `NormalizedFramePayload.imageBuffer`.
    private func makePixelBuffer(from frame: NormalizedFrame) throws -> CVPixelBuffer {
        let pixelFormat: OSType
        switch frame.pixelFormat {
        case .bgra:
            pixelFormat = kCVPixelFormatType_32BGRA
        case .nv12:
            pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        case .i420:
            pixelFormat = kCVPixelFormatType_420YpCbCr8Planar
        default:
            throw MediaCoreError.unsupportedPixelFormat(frame.pixelFormat)
        }

        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            frame.width,
            frame.height,
            pixelFormat,
            attrs as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw MediaCoreError.pipelineFailed("CVPixelBufferCreate failed: \(status)")
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let bytes = frame.pixelBuffer
        if frame.pixelFormat == .bgra || frame.pixelFormat == .i420 {
            guard let dest = CVPixelBufferGetBaseAddress(buffer) else {
                throw MediaCoreError.pipelineFailed("CVPixelBuffer base address nil")
            }
            let destBytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let srcStride = max(frame.stride, 1)
            let height = frame.height
            bytes.withUnsafeBytes { src in
                guard let base = src.baseAddress else { return }
                for row in 0..<height {
                    let srcOffset = row * srcStride
                    let dstOffset = row * destBytesPerRow
                    let count = min(srcStride, destBytesPerRow, bytes.count - srcOffset)
                    guard count > 0, srcOffset + count <= bytes.count else { continue }
                    memcpy(dest.advanced(by: dstOffset), base.advanced(by: srcOffset), count)
                }
            }
        } else if frame.pixelFormat == .nv12 {
            // Expect tightly packed NV12 in the byte payload.
            let ySize = frame.width * frame.height
            let uvSize = ySize / 2
            guard bytes.count >= ySize + uvSize,
                  let yPlane = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
                  let uvPlane = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)
            else {
                throw MediaCoreError.pipelineFailed("NV12 plane copy failed")
            }
            bytes.withUnsafeBytes { src in
                guard let base = src.baseAddress else { return }
                memcpy(yPlane, base, ySize)
                memcpy(uvPlane, base.advanced(by: ySize), uvSize)
            }
        }

        return buffer
    }

    private static func annexBData(from sample: CMSampleBuffer) throws -> Data {
        guard let format = CMSampleBufferGetFormatDescription(sample) else {
            throw MediaCoreError.pipelineFailed("missing format description")
        }
        var out = Data()
        let startCode = Data([0x00, 0x00, 0x00, 0x01])

        // Prepend VPS/SPS/PPS on keyframes so the TS stream is decodable mid-join.
        let isKeyframe: Bool = {
            guard
                let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false),
                CFArrayGetCount(attachments) > 0
            else { return true }
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
            let key = Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque()
            return CFDictionaryGetValue(dict, key) == nil
        }()

        if isKeyframe {
            var paramSetCount = 0
            CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                format,
                parameterSetIndex: 0,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: nil,
                parameterSetCountOut: &paramSetCount,
                nalUnitHeaderLengthOut: nil
            )
            for i in 0..<paramSetCount {
                var ptr: UnsafePointer<UInt8>?
                var size = 0
                let st = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                    format,
                    parameterSetIndex: i,
                    parameterSetPointerOut: &ptr,
                    parameterSetSizeOut: &size,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                )
                if st == noErr, let ptr, size > 0 {
                    out.append(startCode)
                    out.append(ptr, count: size)
                }
            }
        }

        guard let block = CMSampleBufferGetDataBuffer(sample) else {
            throw MediaCoreError.pipelineFailed("missing sample data buffer")
        }
        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let st = CMBlockBufferGetDataPointer(
            block,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard st == kCMBlockBufferNoErr, let dataPointer, totalLength > 0 else {
            throw MediaCoreError.pipelineFailed("CMBlockBufferGetDataPointer failed")
        }

        var offset = 0
        let nalLengthSize = 4
        let raw = UnsafeRawPointer(dataPointer)
        while offset + nalLengthSize <= totalLength {
            let nalLength = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian)
            offset += nalLengthSize
            guard nalLength > 0, offset + nalLength <= totalLength else { break }
            out.append(startCode)
            out.append(Data(bytes: raw.advanced(by: offset), count: nalLength))
            offset += nalLength
        }
        return out
    }
}
