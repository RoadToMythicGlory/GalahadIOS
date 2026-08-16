import Foundation
#if canImport(CoreImage) && canImport(CoreVideo)
import CoreImage
import CoreVideo
#endif

/// Normalizer that guarantees the encoder only ever sees frames at the
/// profile's exact dimensions (the 16:9 catalog sizes). Hardware buffers that
/// don't match — portrait-rotated camera frames, device-native screen capture —
/// are aspect-fit into a pooled output buffer with black letterbox/pillarbox
/// bars. Buffers that already match pass through zero-copy, so the landscape
/// camera path pays nothing.
public actor AspectFitFrameNormalizer: FrameNormalizer {
    public let supportedInputFormats: [PixelFormat]
    public let outputFormat: PixelFormat

    private var targetWidth = 0
    private var targetHeight = 0

    #if canImport(CoreImage) && canImport(CoreVideo)
    private var pool: CVPixelBufferPool?
    private var poolPixelFormat: OSType = 0
    private let context = CIContext(options: [.cacheIntermediates: false])
    #endif

    public init(format: PixelFormat = .nv12) {
        self.supportedInputFormats = [format]
        self.outputFormat = format
    }

    public func prepare(profile: VideoProfile) async throws {
        targetWidth = profile.width
        targetHeight = profile.height
        #if canImport(CoreImage) && canImport(CoreVideo)
        pool = nil
        poolPixelFormat = 0
        #endif
    }

    /// Byte-payload path (harness/tests): same passthrough contract as
    /// `PassthroughFrameNormalizer`; the product path uses hardware buffers.
    public func normalize(
        raw: Data,
        width: Int,
        height: Int,
        inputFormat: PixelFormat,
        presentationTime: Duration,
        captureTimestamp: ContinuousClock.Instant
    ) async throws -> NormalizedFrame {
        guard supportedInputFormats.contains(inputFormat) else {
            throw MediaCoreError.unsupportedPixelFormat(inputFormat)
        }
        return NormalizedFrame(
            pixelBuffer: raw,
            width: width,
            height: height,
            pixelFormat: outputFormat,
            presentationTime: presentationTime,
            captureTimestamp: captureTimestamp,
            stride: width
        )
    }

    public func normalize(_ frame: NormalizedFrame) async throws -> NormalizedFrame {
        guard targetWidth > 0, targetHeight > 0 else { return frame }
        guard frame.width != targetWidth || frame.height != targetHeight else { return frame }
        #if canImport(CoreImage) && canImport(CoreVideo)
        guard case .imageBuffer(let source) = frame.payload else { return frame }
        let output = try render(source)
        let stride = CVPixelBufferGetPlaneCount(output) > 0
            ? CVPixelBufferGetBytesPerRowOfPlane(output, 0)
            : CVPixelBufferGetBytesPerRow(output)
        return NormalizedFrame(
            payload: .imageBuffer(output),
            width: targetWidth,
            height: targetHeight,
            pixelFormat: frame.pixelFormat,
            presentationTime: frame.presentationTime,
            captureTimestamp: frame.captureTimestamp,
            stride: stride
        )
        #else
        return frame
        #endif
    }

    public func teardown() async {
        #if canImport(CoreImage) && canImport(CoreVideo)
        pool = nil
        poolPixelFormat = 0
        #endif
        targetWidth = 0
        targetHeight = 0
    }

    #if canImport(CoreImage) && canImport(CoreVideo)
    private func render(_ source: CVPixelBuffer) throws -> CVPixelBuffer {
        // Output buffers keep the source's CV pixel format (NV12 or BGRA), so
        // VideoToolbox receives the same format it would have on passthrough.
        let format = CVPixelBufferGetPixelFormatType(source)
        if pool == nil || poolPixelFormat != format {
            var newPool: CVPixelBufferPool?
            let attributes: [CFString: Any] = [
                kCVPixelBufferWidthKey: targetWidth,
                kCVPixelBufferHeightKey: targetHeight,
                kCVPixelBufferPixelFormatTypeKey: format,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            ]
            let status = CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                nil,
                attributes as CFDictionary,
                &newPool
            )
            guard status == kCVReturnSuccess, let newPool else {
                throw MediaCoreError.pipelineFailed("CVPixelBufferPoolCreate failed: \(status)")
            }
            pool = newPool
            poolPixelFormat = format
        }

        var created: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool!, &created)
        guard status == kCVReturnSuccess, let outputBuffer = created else {
            throw MediaCoreError.pipelineFailed("CVPixelBufferPoolCreatePixelBuffer failed: \(status)")
        }

        let image = CIImage(cvPixelBuffer: source)
        let sourceExtent = image.extent
        guard sourceExtent.width > 0, sourceExtent.height > 0 else {
            throw MediaCoreError.pipelineFailed("aspect-fit source has empty extent")
        }
        let scale = min(
            CGFloat(targetWidth) / sourceExtent.width,
            CGFloat(targetHeight) / sourceExtent.height
        )
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let tx = ((CGFloat(targetWidth) - scaled.extent.width) / 2 - scaled.extent.minX).rounded()
        let ty = ((CGFloat(targetHeight) - scaled.extent.height) / 2 - scaled.extent.minY).rounded()
        let positioned = scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty))
        let bounds = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        let composited = positioned.composited(over: CIImage(color: .black).cropped(to: bounds))
        context.render(composited, to: outputBuffer)
        return outputBuffer
    }
    #endif
}
