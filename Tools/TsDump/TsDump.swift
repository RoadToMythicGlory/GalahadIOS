import Foundation
import MediaCore

/// Writes a synthetic MPEG-TS file through the production `MpegTsStreamMuxer`
/// so the container structure (PAT/PMT/PES/PCR/continuity) can be validated
/// with real demuxers (ffprobe/tsduck/VLC) without a device:
///
///     swift run galahad-ts-dump out.ts
///     ffprobe -show_programs -show_streams out.ts
///
/// Payloads are placeholder NAL/ADTS bytes (not decodable video), so decoders
/// will report the elementary streams from the PMT but cannot render frames.
enum TsDump {
    static func run() async throws {
        let arguments = CommandLine.arguments
        let path = arguments.count > 1 ? arguments[1] : "galahad-sample.ts"

        let profile = QualityPreset.resolveOrDefault(id: QualityPreset.defaultPresetId).asVideoProfile
        let muxer = MpegTsStreamMuxer()
        try await muxer.configure(profile: profile, includeAudio: true)

        var out = Data()
        let clock = ContinuousClock.now

        for i in 0..<90 { // 3 seconds of 30 fps synthetic access units
            var au = Data([0x00, 0x00, 0x00, 0x01, 0x40, 0x01]) // VPS-typed NAL
            au.append(Data([0x00, 0x00, 0x00, 0x01, 0x26, 0x01])) // IDR-typed NAL
            au.append(Data(repeating: UInt8(truncatingIfNeeded: i), count: 2000))
            let unit = EncodedAccessUnit(
                data: au,
                presentationTime: .milliseconds(Int64(i) * 1000 / 30),
                encodeStarted: clock,
                encodeFinished: clock,
                width: profile.width,
                height: profile.height
            )
            if let chunk = try await muxer.pushVideo(unit) {
                out.append(chunk)
            }

            // ~1 ADTS AAC packet per video frame (placeholder payload).
            var adts = Data([0xFF, 0xF1, 0x4C, 0x80, 0x0D, 0x3F, 0xFC])
            adts.append(Data(repeating: 0x55, count: 96))
            if let chunk = try await muxer.pushAudioAAC(
                adts,
                presentationTime: .milliseconds(Int64(i) * 1000 / 30)
            ) {
                out.append(chunk)
            }
        }
        out.append(try await muxer.finalize())

        try out.write(to: URL(fileURLWithPath: path))
        print("wrote \(out.count) bytes (\(out.count / 188) TS cells) to \(path)")
    }
}

try await TsDump.run()
