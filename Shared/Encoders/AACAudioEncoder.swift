import AVFoundation
import CoreMedia
import Foundation
import MediaCore

/// Streams capture PCM (`CMSampleBuffer` from AVCaptureAudioDataOutput or
/// ReplayKit `.audioApp` / `.audioMic`) into AAC-LC packets framed with ADTS
/// headers, ready for `MpegTsMuxer.pushAudioAAC` (TS stream_type 0x0F).
///
/// All work is confined to an internal serial queue; `encode(sampleBuffer:)`
/// is safe to call from any capture callback thread. Packets are delivered on
/// that queue via `onPacket` with a monotonically increasing presentation time
/// derived from the first buffer's PTS plus consumed sample count.
public final class AACAudioEncoder: @unchecked Sendable {
    public static let samplesPerPacket: Int64 = 1024

    private let queue = DispatchQueue(label: "gg.galahad.audio.aac")
    private let onPacket: @Sendable (Data, Duration) -> Void

    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var pendingPCM: [AVAudioPCMBuffer] = []
    private var basePTS: Duration?
    private var packetsDelivered: Int64 = 0
    private var outputSampleRate: Double = 48_000
    private var outputChannels: UInt32 = 2
    private var failed = false

    public init(onPacket: @escaping @Sendable (Data, Duration) -> Void) {
        self.onPacket = onPacket
    }

    /// Feed one capture buffer. Invalid/unsupported buffers are dropped silently
    /// after the first failure is reported through the packet callback path.
    public func encode(sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              CMSampleBufferGetNumSamples(sampleBuffer) > 0
        else { return }
        queue.async { [self] in
            encodeOnQueue(sampleBuffer)
        }
    }

    public func reset() {
        queue.async { [self] in
            converter = nil
            inputFormat = nil
            outputFormat = nil
            pendingPCM = []
            basePTS = nil
            packetsDelivered = 0
            failed = false
        }
    }

    // MARK: - Queue-confined

    private func encodeOnQueue(_ sampleBuffer: CMSampleBuffer) {
        guard !failed else { return }
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }

        // Build the converter lazily; rebuild if the capture format changes
        // mid-stream (e.g. audio route change).
        let liveFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        if converter == nil
            || liveFormat.sampleRate != inputFormat?.sampleRate
            || liveFormat.channelCount != inputFormat?.channelCount {
            pendingPCM = []
            guard configureConverter(with: formatDescription) else {
                failed = true
                return
            }
        }
        guard let converter, let inputFormat else { return }

        guard let pcm = makePCMBuffer(from: sampleBuffer, format: inputFormat) else {
            return
        }

        if basePTS == nil {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            basePTS = Self.duration(from: pts)
        }

        pendingPCM.append(pcm)
        drain(converter: converter)
    }

    private func configureConverter(with formatDescription: CMAudioFormatDescription) -> Bool {
        let input = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        outputSampleRate = Self.nearestAACSampleRate(input.sampleRate)
        outputChannels = min(max(input.channelCount, 1), 2)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: outputSampleRate,
            AVNumberOfChannelsKey: outputChannels,
        ]
        guard
            let output = AVAudioFormat(settings: settings),
            let converter = AVAudioConverter(from: input, to: output)
        else {
            return false
        }
        converter.bitRate = outputChannels > 1 ? 128_000 : 96_000
        self.inputFormat = input
        self.outputFormat = output
        self.converter = converter
        return true
    }

    private func makePCMBuffer(from sampleBuffer: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return nil }
        pcm.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: pcm.mutableAudioBufferList
        )
        return status == noErr ? pcm : nil
    }

    private func drain(converter: AVAudioConverter) {
        guard let outputFormat else { return }
        while true {
            let compressed = AVAudioCompressedBuffer(
                format: outputFormat,
                packetCapacity: 8,
                maximumPacketSize: 1536
            )

            var conversionError: NSError?
            let status = converter.convert(to: compressed, error: &conversionError) { [self] _, outStatus in
                if pendingPCM.isEmpty {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                outStatus.pointee = .haveData
                return pendingPCM.removeFirst()
            }

            if compressed.packetCount > 0 {
                deliver(compressed)
            }
            switch status {
            case .haveData:
                continue
            case .inputRanDry, .endOfStream:
                return
            case .error:
                failed = conversionError != nil
                return
            @unknown default:
                return
            }
        }
    }

    private func deliver(_ compressed: AVAudioCompressedBuffer) {
        guard let descriptions = compressed.packetDescriptions else { return }
        let base = compressed.data
        for i in 0..<Int(compressed.packetCount) {
            let description = descriptions[i]
            let start = Int(description.mStartOffset)
            let length = Int(description.mDataByteSize)
            guard length > 0 else { continue }
            let aac = Data(bytes: base.advanced(by: start), count: length)

            var packet = Self.adtsHeader(
                payloadLength: length,
                sampleRate: outputSampleRate,
                channels: outputChannels
            )
            packet.append(aac)

            let elapsedSamples = packetsDelivered * Self.samplesPerPacket
            let offset = Duration.nanoseconds(
                Int64(Double(elapsedSamples) * 1_000_000_000.0 / outputSampleRate)
            )
            let pts = (basePTS ?? .zero) + offset
            packetsDelivered += 1
            onPacket(packet, pts)
        }
    }

    // MARK: - ADTS

    private static let adtsSampleRates: [Double] = [
        96_000, 88_200, 64_000, 48_000, 44_100, 32_000,
        24_000, 22_050, 16_000, 12_000, 11_025, 8_000,
    ]

    static func nearestAACSampleRate(_ rate: Double) -> Double {
        adtsSampleRates.min(by: { abs($0 - rate) < abs($1 - rate) }) ?? 48_000
    }

    /// 7-byte ADTS header (no CRC), AAC-LC.
    static func adtsHeader(payloadLength: Int, sampleRate: Double, channels: UInt32) -> Data {
        let frequencyIndex = UInt8(adtsSampleRates.firstIndex(of: sampleRate) ?? 3)
        let channelConfig = UInt8(min(channels, 7))
        let frameLength = UInt16(payloadLength + 7)

        var header = Data(capacity: 7)
        header.append(0xFF)
        header.append(0xF1) // MPEG-4, layer 0, no CRC
        // profile AAC-LC (object type 2 → '01'), frequency index, channel config MSB
        header.append((0b01 << 6) | (frequencyIndex << 2) | ((channelConfig >> 2) & 0x01))
        header.append(((channelConfig & 0x03) << 6) | UInt8((frameLength >> 11) & 0x03))
        header.append(UInt8((frameLength >> 3) & 0xFF))
        header.append((UInt8(frameLength & 0x07) << 5) | 0x1F) // buffer fullness MSBs
        header.append(0xFC) // buffer fullness LSBs + 1 raw data block
        return header
    }

    static func duration(from time: CMTime) -> Duration {
        guard time.isNumeric else { return .zero }
        return .nanoseconds(Int64(CMTimeGetSeconds(time) * 1_000_000_000))
    }
}
