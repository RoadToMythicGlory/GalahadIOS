import Foundation

/// Standards-conformant MPEG-TS muxer for the production path:
/// HEVC video (stream_type 0x24) or H.264 video (stream_type 0x1B),
/// plus optional ADTS AAC audio (stream_type 0x0F).
///
/// Emits real PAT/PMT sections (with MPEG-2 CRC32), PES packets with PTS,
/// PCR on the video PID, per-PID continuity counters, and adaptation-field
/// stuffing so every cell is exactly 188 bytes. Output is aligned to
/// 1316-byte chunks (7 × 188) to match preferred SRT payload packing;
/// any tail shorter than 1316 bytes is held until the next push or `finalize()`.
///
/// This replaces GStreamer `mpegtsmux` in the app pipeline: encoded HEVC
/// access units (Annex-B) go straight from VideoToolbox through this muxer
/// into the SRT transport.
public actor MpegTsStreamMuxer: MpegTsMuxer {
    // MARK: Constants

    private static let packetSize = 188
    private static let chunkSize = 1316 // 7 × 188, preferred SRT payload
    private static let patPID: UInt16 = 0x0000
    private static let pmtPID: UInt16 = 0x1000
    private static let videoPID: UInt16 = 0x0100
    private static let audioPID: UInt16 = 0x0101
    private static let nullPID: UInt16 = 0x1FFF
    private static let programNumber: UInt16 = 1
    private static let hevcStreamType: UInt8 = 0x24
    private static let h264StreamType: UInt8 = 0x1B
    private static let adtsAACStreamType: UInt8 = 0x0F
    /// Offset added to all timestamps so PCR can lead PTS without going negative.
    private static let ptsOffsetTicks: Int64 = 90_000 // 1 s @ 90 kHz
    /// PCR leads PTS by this amount (must be < 1 s per ISO 13818-1 STD model).
    private static let pcrLeadTicks: Int64 = 27_000 // 300 ms @ 90 kHz
    /// Re-emit PAT/PMT at least this often (video access units).
    private static let tableRepeatInterval = 30

    // MARK: State

    private let codec: VideoCodec
    private var profile: VideoProfile?
    private var includeAudio = false
    private var continuity: [UInt16: UInt8] = [:]
    private var videoUnitsSinceTables = 0
    private var patVersion: UInt8 = 0
    /// Complete 188-byte cells not yet released (kept for 1316 alignment).
    private var pending = Data()

    public init(codec: VideoCodec = .hevc) {
        self.codec = codec
    }

    // MARK: MpegTsMuxer

    public func configure(profile: VideoProfile, includeAudio: Bool) async throws {
        self.profile = profile
        self.includeAudio = includeAudio
        continuity = [:]
        pending = Data()
        videoUnitsSinceTables = 0
        emitTables()
    }

    public func pushVideo(_ unit: EncodedAccessUnit) async throws -> Data? {
        guard profile != nil else { throw MediaCoreError.notConfigured("MpegTsMuxer") }

        if videoUnitsSinceTables >= Self.tableRepeatInterval {
            emitTables()
        }
        videoUnitsSinceTables += 1

        var accessUnit = unit.data
        if !startsWithAccessUnitDelimiter(accessUnit) {
            switch codec {
            case .hevc:
                // HEVC AUD NAL (type 35), pic_type "any".
                accessUnit = Data([0x00, 0x00, 0x00, 0x01, 0x46, 0x01, 0x50]) + accessUnit
            case .h264:
                // H.264 AUD NAL (type 9), primary_pic_type "any".
                accessUnit = Data([0x00, 0x00, 0x00, 0x01, 0x09, 0xF0]) + accessUnit
            }
        }

        let ptsTicks = Self.ticks90kHz(from: unit.presentationTime) + Self.ptsOffsetTicks
        let pes = makePESPacket(
            streamID: 0xE0,
            payload: accessUnit,
            ptsTicks: ptsTicks,
            unboundedLength: true
        )
        packetize(
            pes: pes,
            pid: Self.videoPID,
            pcrTicks: max(ptsTicks - Self.pcrLeadTicks, 0),
            randomAccess: isKeyframe(accessUnit)
        )
        return releaseAlignedChunks()
    }

    public func pushAudioAAC(_ packet: Data, presentationTime: Duration) async throws -> Data? {
        guard profile != nil else { throw MediaCoreError.notConfigured("MpegTsMuxer") }
        guard includeAudio, !packet.isEmpty else { return nil }

        let ptsTicks = Self.ticks90kHz(from: presentationTime) + Self.ptsOffsetTicks
        let pes = makePESPacket(
            streamID: 0xC0,
            payload: packet,
            ptsTicks: ptsTicks,
            unboundedLength: false
        )
        packetize(pes: pes, pid: Self.audioPID, pcrTicks: nil, randomAccess: false)
        return releaseAlignedChunks()
    }

    /// Flushes any buffered tail, padded to a full 1316-byte chunk with null packets.
    public func finalize() async throws -> Data {
        guard !pending.isEmpty else { return Data() }
        while pending.count % Self.chunkSize != 0 {
            appendPacket(makeNullPacket())
        }
        let out = pending
        pending = Data()
        return out
    }

    public func teardown() async {
        profile = nil
        pending = Data()
        continuity = [:]
        videoUnitsSinceTables = 0
    }

    // MARK: PSI (PAT / PMT)

    private func emitTables() {
        packetizeSection(makePATSection(), pid: Self.patPID)
        packetizeSection(makePMTSection(), pid: Self.pmtPID)
        videoUnitsSinceTables = 0
    }

    private func makePATSection() -> Data {
        var body = Data()
        body.appendUInt16(Self.programNumber)
        body.appendUInt16(0xE000 | Self.pmtPID) // reserved '111' + PMT PID
        return makeSection(tableID: 0x00, tableIDExtension: 0x0001, body: body)
    }

    private func makePMTSection() -> Data {
        var body = Data()
        body.appendUInt16(0xE000 | Self.videoPID) // PCR PID
        body.appendUInt16(0xF000) // program_info_length = 0

        body.append(codec == .h264 ? Self.h264StreamType : Self.hevcStreamType)
        body.appendUInt16(0xE000 | Self.videoPID)
        body.appendUInt16(0xF000) // ES_info_length = 0

        if includeAudio {
            body.append(Self.adtsAACStreamType)
            body.appendUInt16(0xE000 | Self.audioPID)
            body.appendUInt16(0xF000)
        }
        return makeSection(tableID: 0x02, tableIDExtension: Self.programNumber, body: body)
    }

    /// Builds a PSI section: header + body + CRC32, prefixed with pointer_field.
    private func makeSection(tableID: UInt8, tableIDExtension: UInt16, body: Data) -> Data {
        let sectionLength = 5 + body.count + 4 // after section_length field, incl. CRC
        var section = Data()
        section.append(tableID)
        // section_syntax_indicator=1, '0', reserved '11', 12-bit length
        section.appendUInt16(0xB000 | UInt16(sectionLength))
        section.appendUInt16(tableIDExtension)
        section.append(0xC1 | (patVersion << 1)) // reserved '11', version, current_next=1
        section.append(0x00) // section_number
        section.append(0x00) // last_section_number
        section.append(body)
        section.appendUInt32(Self.crc32MPEG(section))
        return Data([0x00]) + section // pointer_field
    }

    /// PSI sections fit in one TS packet here (PAT/PMT are tiny).
    private func packetizeSection(_ section: Data, pid: UInt16) {
        precondition(section.count <= Self.packetSize - 4, "PSI section exceeds one TS packet")
        var packet = Data(capacity: Self.packetSize)
        packet.append(0x47)
        packet.appendUInt16(0x4000 | (pid & 0x1FFF)) // payload_unit_start_indicator = 1
        packet.append(0x10 | nextContinuity(pid: pid)) // payload only
        packet.append(section)
        if packet.count < Self.packetSize {
            packet.append(Data(repeating: 0xFF, count: Self.packetSize - packet.count))
        }
        appendPacket(packet)
    }

    // MARK: PES

    private func makePESPacket(
        streamID: UInt8,
        payload: Data,
        ptsTicks: Int64,
        unboundedLength: Bool
    ) -> Data {
        let headerDataLength = 5 // PTS only
        var pes = Data()
        pes.append(contentsOf: [0x00, 0x00, 0x01, streamID])
        let afterLength = 3 + headerDataLength + payload.count
        if unboundedLength || afterLength > 0xFFFF {
            pes.appendUInt16(0x0000) // unbounded, allowed for video
        } else {
            pes.appendUInt16(UInt16(afterLength))
        }
        pes.append(0x80) // marker '10', no scrambling, no priority/alignment/copyright
        pes.append(0x80) // PTS_DTS_flags = '10' (PTS only)
        pes.append(UInt8(headerDataLength))
        pes.append(encodePTS(ptsTicks, prefix: 0b0010))
        pes.append(payload)
        return pes
    }

    /// 33-bit PTS in the 5-byte marker-bit format.
    private func encodePTS(_ ticks: Int64, prefix: UInt8) -> Data {
        let v = UInt64(bitPattern: ticks) & 0x1_FFFF_FFFF
        var out = Data(capacity: 5)
        out.append((prefix << 4) | UInt8((v >> 29) & 0x0E) | 0x01)
        out.append(UInt8((v >> 22) & 0xFF))
        out.append(UInt8((v >> 14) & 0xFE) | 0x01)
        out.append(UInt8((v >> 7) & 0xFF))
        out.append(UInt8((v << 1) & 0xFE) | 0x01)
        return out
    }

    // MARK: TS packetization

    /// Splits a PES packet into 188-byte TS cells with continuity counters,
    /// optional PCR on the first cell, and stuffing via adaptation field.
    private func packetize(pes: Data, pid: UInt16, pcrTicks: Int64?, randomAccess: Bool) {
        func payloadCapacity(_ adaptation: Data?) -> Int {
            // 184 bytes after the 4-byte header, minus adaptation length byte + body.
            184 - (adaptation.map { 1 + $0.count } ?? 0)
        }

        var offset = 0
        var first = true

        while offset < pes.count {
            let remaining = pes.count - offset

            var adaptation: Data?
            if first, pcrTicks != nil || randomAccess {
                var field = Data()
                var flags: UInt8 = 0
                if randomAccess { flags |= 0x40 }
                if pcrTicks != nil { flags |= 0x10 }
                field.append(flags)
                if let pcrTicks {
                    field.append(encodePCR(pcrTicks))
                }
                adaptation = field
            }

            if remaining < payloadCapacity(adaptation) {
                // Absorb the gap with adaptation-field stuffing so the cell is 188 bytes.
                let gap = payloadCapacity(adaptation) - remaining
                if var field = adaptation {
                    field.append(Data(repeating: 0xFF, count: gap))
                    adaptation = field
                } else if gap == 1 {
                    adaptation = Data() // adaptation_field_length = 0: one stuffing byte
                } else {
                    var field = Data([0x00]) // flags byte, no indicators
                    field.append(Data(repeating: 0xFF, count: gap - 2))
                    adaptation = field
                }
            }

            var packet = Data(capacity: Self.packetSize)
            packet.append(0x47)
            packet.appendUInt16((first ? 0x4000 : 0x0000) | (pid & 0x1FFF))
            packet.append((adaptation != nil ? 0x30 : 0x10) | nextContinuity(pid: pid))
            if let adaptation {
                packet.append(UInt8(adaptation.count))
                packet.append(adaptation)
            }

            let take = min(payloadCapacity(adaptation), remaining)
            packet.append(pes.subdata(in: offset..<(offset + take)))
            offset += take
            first = false

            precondition(packet.count == Self.packetSize, "TS cell must be 188 bytes")
            appendPacket(packet)
        }
    }

    /// 48-bit PCR field: 33-bit base (90 kHz), 6 reserved bits, 9-bit extension.
    private func encodePCR(_ ticks: Int64) -> Data {
        let base = UInt64(bitPattern: ticks) & 0x1_FFFF_FFFF
        let ext: UInt64 = 0
        var out = Data(capacity: 6)
        out.append(UInt8((base >> 25) & 0xFF))
        out.append(UInt8((base >> 17) & 0xFF))
        out.append(UInt8((base >> 9) & 0xFF))
        out.append(UInt8((base >> 1) & 0xFF))
        out.append(UInt8((base << 7) & 0x80) | 0x7E | UInt8((ext >> 8) & 0x01))
        out.append(UInt8(ext & 0xFF))
        return out
    }

    private func makeNullPacket() -> Data {
        var packet = Data(capacity: Self.packetSize)
        packet.append(0x47)
        packet.appendUInt16(Self.nullPID)
        packet.append(0x10) // continuity counter undefined for null packets
        packet.append(Data(repeating: 0xFF, count: Self.packetSize - 4))
        return packet
    }

    private func nextContinuity(pid: UInt16) -> UInt8 {
        let value = continuity[pid] ?? 0
        continuity[pid] = (value + 1) & 0x0F
        return value
    }

    private func appendPacket(_ packet: Data) {
        pending.append(packet)
    }

    /// Releases the largest 1316-multiple prefix of buffered cells.
    private func releaseAlignedChunks() -> Data? {
        let alignedCount = (pending.count / Self.chunkSize) * Self.chunkSize
        guard alignedCount > 0 else { return nil }
        let out = pending.prefix(alignedCount)
        pending.removeSubrange(0..<alignedCount)
        return Data(out)
    }

    // MARK: NAL helpers (codec-aware)

    private func startsWithAccessUnitDelimiter(_ annexB: Data) -> Bool {
        let audType: UInt8 = codec == .h264 ? 9 : 35
        return forEachNALType(in: annexB, limit: 1) { $0 == audType }
    }

    private func isKeyframe(_ annexB: Data) -> Bool {
        switch codec {
        case .hevc:
            // IRAP (16...23) or parameter sets (VPS 32 / SPS 33 / PPS 34).
            return forEachNALType(in: annexB, limit: 8) { type in
                (16...23).contains(type) || (32...34).contains(type)
            }
        case .h264:
            // IDR (5) or parameter sets (SPS 7 / PPS 8).
            return forEachNALType(in: annexB, limit: 8) { type in
                type == 5 || type == 7 || type == 8
            }
        }
    }

    /// Scans Annex-B start codes and tests up to `limit` NAL types with `predicate`.
    private func forEachNALType(in data: Data, limit: Int, predicate: (UInt8) -> Bool) -> Bool {
        var found = 0
        var i = data.startIndex
        let end = data.endIndex
        while i < end - 3, found < limit {
            if data[i] == 0x00, data[i + 1] == 0x00 {
                var nalStart: Data.Index?
                if data[i + 2] == 0x01 {
                    nalStart = i + 3
                } else if i < end - 4, data[i + 2] == 0x00, data[i + 3] == 0x01 {
                    nalStart = i + 4
                }
                if let nalStart, nalStart < end {
                    let type = codec == .h264
                        ? data[nalStart] & 0x1F
                        : (data[nalStart] >> 1) & 0x3F
                    if predicate(type) { return true }
                    found += 1
                    i = nalStart
                    continue
                }
            }
            i += 1
        }
        return false
    }

    // MARK: Time

    /// Converts a `Duration` to 90 kHz MPEG ticks.
    static func ticks90kHz(from duration: Duration) -> Int64 {
        let c = duration.components
        // 90_000 ticks per second; 1e18 attoseconds per second → ×9 / 1e14.
        return c.seconds * 90_000 + (c.attoseconds * 9) / 100_000_000_000_000
    }

    // MARK: CRC32 (MPEG-2)

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var crc = UInt32(i) << 24
            for _ in 0..<8 {
                crc = (crc & 0x8000_0000) != 0 ? (crc << 1) ^ 0x04C1_1DB7 : crc << 1
            }
            return crc
        }
    }()

    static func crc32MPEG(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = (crc << 8) ^ crcTable[Int((crc >> 24) ^ UInt32(byte)) & 0xFF]
        }
        return crc
    }
}

// MARK: - Big-endian append helpers

extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}
