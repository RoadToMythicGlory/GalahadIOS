import XCTest
@testable import MediaCore

final class MpegTsStreamMuxerTests: XCTestCase {
    private struct TSPacket {
        var pid: UInt16
        var payloadUnitStart: Bool
        var continuity: UInt8
        var hasAdaptation: Bool
        var hasPayload: Bool
        var adaptation: Data
        var payload: Data
    }

    private func parsePackets(_ data: Data) throws -> [TSPacket] {
        XCTAssertEqual(data.count % 188, 0, "stream must be whole 188-byte cells")
        var packets: [TSPacket] = []
        var offset = 0
        while offset + 188 <= data.count {
            let cell = data.subdata(in: offset..<(offset + 188))
            XCTAssertEqual(cell[0], 0x47, "sync byte")
            let pid = (UInt16(cell[1] & 0x1F) << 8) | UInt16(cell[2])
            let pusi = (cell[1] & 0x40) != 0
            let control = (cell[3] >> 4) & 0x03
            let continuity = cell[3] & 0x0F
            let hasAdaptation = (control & 0x02) != 0
            let hasPayload = (control & 0x01) != 0
            var body = 4
            var adaptation = Data()
            if hasAdaptation {
                let length = Int(cell[4])
                adaptation = cell.subdata(in: 5..<(5 + length))
                body = 5 + length
            }
            packets.append(TSPacket(
                pid: pid,
                payloadUnitStart: pusi,
                continuity: continuity,
                hasAdaptation: hasAdaptation,
                hasPayload: hasPayload,
                adaptation: adaptation,
                payload: hasPayload ? cell.subdata(in: body..<188) : Data()
            ))
            offset += 188
        }
        return packets
    }

    private func makeAccessUnit(size: Int, ptsMilliseconds: Int64) -> EncodedAccessUnit {
        // Fake Annex-B: VPS(32) + IDR_W_RADL(19) so keyframe detection triggers.
        var data = Data([0x00, 0x00, 0x00, 0x01, 0x40, 0x01])
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x01, 0x26, 0x01])
        data.append(Data(repeating: 0xAB, count: max(size - data.count, 0)))
        let now = ContinuousClock.now
        return EncodedAccessUnit(
            data: data,
            presentationTime: .milliseconds(ptsMilliseconds),
            encodeStarted: now,
            encodeFinished: now,
            width: 1280,
            height: 720
        )
    }

    func testEmitsAligned188And1316Chunks() async throws {
        let muxer = MpegTsStreamMuxer()
        try await muxer.configure(
            profile: QualityPreset.find(id: "720p30")!.asVideoProfile,
            includeAudio: false
        )
        var emitted = Data()
        if let chunk = try await muxer.pushVideo(makeAccessUnit(size: 4000, ptsMilliseconds: 0)) {
            XCTAssertEqual(chunk.count % 1316, 0, "released chunks are 1316-aligned")
            emitted.append(chunk)
        }
        let tail = try await muxer.finalize()
        XCTAssertEqual(tail.count % 1316, 0, "finalize pads the tail to 1316")
        emitted.append(tail)

        XCTAssertGreaterThan(emitted.count, 0)
        _ = try parsePackets(emitted) // validates sync bytes + cell size
    }

    func testPATAndPMTAreValidWithCRC() async throws {
        let muxer = MpegTsStreamMuxer()
        try await muxer.configure(
            profile: QualityPreset.find(id: "720p30")!.asVideoProfile,
            includeAudio: true
        )
        var stream = Data()
        if let chunk = try await muxer.pushVideo(makeAccessUnit(size: 3000, ptsMilliseconds: 0)) {
            stream.append(chunk)
        }
        stream.append(try await muxer.finalize())
        let packets = try parsePackets(stream)

        // First two cells are PAT then PMT.
        XCTAssertEqual(packets[0].pid, 0x0000)
        XCTAssertTrue(packets[0].payloadUnitStart)
        XCTAssertEqual(packets[1].pid, 0x1000)

        func section(of packet: TSPacket) -> Data {
            let pointer = Int(packet.payload[packet.payload.startIndex])
            let start = packet.payload.startIndex + 1 + pointer
            let lengthHigh = Int(packet.payload[start + 1] & 0x0F)
            let lengthLow = Int(packet.payload[start + 2])
            let total = 3 + (lengthHigh << 8 | lengthLow)
            return packet.payload.subdata(in: start..<(start + total))
        }

        for packet in [packets[0], packets[1]] {
            let s = section(of: packet)
            let body = s.prefix(s.count - 4)
            let storedCRC = s.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            XCTAssertEqual(MpegTsStreamMuxer.crc32MPEG(Data(body)), storedCRC, "CRC32/MPEG-2 must match")
        }

        // PAT points at PMT PID 0x1000.
        let pat = section(of: packets[0])
        let pmtPID = (UInt16(pat[pat.startIndex + 10] & 0x1F) << 8) | UInt16(pat[pat.startIndex + 11])
        XCTAssertEqual(pmtPID, 0x1000)

        // PMT lists HEVC (0x24) on 0x0100 and ADTS AAC (0x0F) on 0x0101.
        let pmt = section(of: packets[1])
        let streams = Data(pmt.dropFirst(12).dropLast(4))
        var streamTypes: [UInt8: UInt16] = [:]
        var i = streams.startIndex
        while i + 5 <= streams.endIndex {
            let type = streams[i]
            let pid = (UInt16(streams[i + 1] & 0x1F) << 8) | UInt16(streams[i + 2])
            streamTypes[type] = pid
            i += 5
        }
        XCTAssertEqual(streamTypes[0x24], 0x0100, "HEVC video ES")
        XCTAssertEqual(streamTypes[0x0F], 0x0101, "ADTS AAC audio ES")
    }

    func testVideoPESHasPTSAndPCRAndAUD() async throws {
        let ptsMs: Int64 = 1250
        let muxer = MpegTsStreamMuxer()
        try await muxer.configure(
            profile: QualityPreset.find(id: "720p30")!.asVideoProfile,
            includeAudio: false
        )
        var stream = Data()
        if let chunk = try await muxer.pushVideo(makeAccessUnit(size: 600, ptsMilliseconds: ptsMs)) {
            stream.append(chunk)
        }
        stream.append(try await muxer.finalize())
        let packets = try parsePackets(stream)
        let video = packets.filter { $0.pid == 0x0100 }
        XCTAssertFalse(video.isEmpty)
        XCTAssertEqual(video.filter(\.payloadUnitStart).count, 1, "one PES start per access unit")

        // First video cell: adaptation with PCR (0x10) + random access (0x40).
        let head = video[0]
        XCTAssertTrue(head.hasAdaptation)
        let flags = head.adaptation[head.adaptation.startIndex]
        XCTAssertEqual(flags & 0x50, 0x50, "PCR + random_access_indicator")

        // Reassemble the PES and verify header + PTS.
        let pes = video.reduce(into: Data()) { $0.append($1.payload) }
        XCTAssertEqual(Array(pes.prefix(4)), [0x00, 0x00, 0x01, 0xE0])
        XCTAssertEqual(pes[pes.startIndex + 7] & 0xC0, 0x80, "PTS-only flags")

        let p = Array(pes.dropFirst(9).prefix(5))
        let decoded: Int64 =
            (Int64(p[0] & 0x0E) << 29) |
            (Int64(p[1]) << 22) |
            (Int64(p[2] & 0xFE) << 14) |
            (Int64(p[3]) << 7) |
            (Int64(p[4]) >> 1)
        let expected = ptsMs * 90 + 90_000 // 90 kHz + muxer PTS offset
        XCTAssertEqual(decoded, expected)

        // Payload begins with an HEVC access-unit delimiter (type 35).
        let payloadStart = pes.startIndex + 9 + 5
        XCTAssertEqual(Array(pes[payloadStart..<(payloadStart + 5)]), [0x00, 0x00, 0x00, 0x01, 0x46])
    }

    func testContinuityCountersIncrementPerPID() async throws {
        let muxer = MpegTsStreamMuxer()
        try await muxer.configure(
            profile: QualityPreset.find(id: "720p30")!.asVideoProfile,
            includeAudio: false
        )
        var emitted = Data()
        for i in 0..<10 {
            if let chunk = try await muxer.pushVideo(makeAccessUnit(size: 900, ptsMilliseconds: Int64(i * 33))) {
                emitted.append(chunk)
            }
        }
        emitted.append(try await muxer.finalize())

        let video = try parsePackets(emitted).filter { $0.pid == 0x0100 && $0.hasPayload }
        for pair in zip(video, video.dropFirst()) {
            XCTAssertEqual((pair.0.continuity + 1) & 0x0F, pair.1.continuity, "no continuity gaps")
        }
    }

    func testAudioPacketsMuxOnAudioPID() async throws {
        let muxer = MpegTsStreamMuxer()
        try await muxer.configure(
            profile: QualityPreset.find(id: "720p30")!.asVideoProfile,
            includeAudio: true
        )
        // ADTS-framed AAC packet stand-in.
        let aac = Data([0xFF, 0xF1, 0x4C, 0x80, 0x20, 0x1F, 0xFC]) + Data(repeating: 0x55, count: 200)
        var stream = Data()
        if let chunk = try await muxer.pushAudioAAC(aac, presentationTime: .milliseconds(100)) {
            stream.append(chunk)
        }
        stream.append(try await muxer.finalize())
        let audio = try parsePackets(stream).filter { $0.pid == 0x0101 }
        XCTAssertFalse(audio.isEmpty)
        XCTAssertEqual(audio.filter(\.payloadUnitStart).count, 1)

        let pes = audio.reduce(into: Data()) { $0.append($1.payload) }
        XCTAssertEqual(Array(pes.prefix(4)), [0x00, 0x00, 0x01, 0xC0])
        // Bounded PES length for audio: 3 header-ext + 5 PTS + payload.
        let length = (Int(pes[pes.startIndex + 4]) << 8) | Int(pes[pes.startIndex + 5])
        XCTAssertEqual(length, 8 + aac.count)
    }

    func testAudioIgnoredWhenNotConfigured() async throws {
        let muxer = MpegTsStreamMuxer()
        try await muxer.configure(
            profile: QualityPreset.find(id: "720p30")!.asVideoProfile,
            includeAudio: false
        )
        let out = try await muxer.pushAudioAAC(Data(repeating: 1, count: 64), presentationTime: .zero)
        XCTAssertNil(out)
    }

    func testCRC32MPEGKnownVector() {
        // CRC-32/MPEG-2 of ASCII "123456789" is 0x0376E6E7.
        XCTAssertEqual(MpegTsStreamMuxer.crc32MPEG(Data("123456789".utf8)), 0x0376_E6E7)
    }

    func testTicks90kHzConversion() {
        XCTAssertEqual(MpegTsStreamMuxer.ticks90kHz(from: .seconds(1)), 90_000)
        XCTAssertEqual(MpegTsStreamMuxer.ticks90kHz(from: .milliseconds(1500)), 135_000)
        XCTAssertEqual(MpegTsStreamMuxer.ticks90kHz(from: .zero), 0)
    }
}
