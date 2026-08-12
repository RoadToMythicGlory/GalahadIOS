import Foundation

/// Collects encoded access units into a simple MPEG-TS-like byte stream for
/// harness validation. The production path uses GStreamer `mpegtsmux`; this
/// file muxer exists so pure-Swift tests can exercise the layer boundary.
public actor FileMpegTsMuxer: MpegTsMuxer {
    private var chunks: [Data] = []
    private var profile: VideoProfile?
    private let packetSize = 188

    public init() {}

    public func configure(profile: VideoProfile, includeAudio: Bool) async throws {
        self.profile = profile
        self.chunks.removeAll(keepingCapacity: true)
        _ = includeAudio
        // PAT/PMT-like sync packets so packetization checks see 188-byte cells.
        chunks.append(makeTSPacket(pid: 0x0000, payload: Data("PAT0".utf8)))
        chunks.append(makeTSPacket(pid: 0x1000, payload: Data("PMT0".utf8)))
    }

    public func pushVideo(_ unit: EncodedAccessUnit) async throws -> Data? {
        guard profile != nil else { throw MediaCoreError.notConfigured("MpegTsMuxer") }
        var emitted = Data()
        var offset = 0
        let data = unit.data
        while offset < data.count {
            let end = min(offset + 184, data.count)
            let slice = data.subdata(in: offset..<end)
            let packet = makeTSPacket(pid: 0x0100, payload: slice)
            chunks.append(packet)
            emitted.append(packet)
            offset = end
        }
        return emitted.isEmpty ? nil : emitted
    }

    public func pushAudioAAC(_ packet: Data, presentationTime: Duration) async throws -> Data? {
        _ = presentationTime
        let ts = makeTSPacket(pid: 0x0101, payload: packet.prefix(184))
        chunks.append(ts)
        return ts
    }

    public func finalize() async throws -> Data {
        chunks.reduce(into: Data()) { $0.append($1) }
    }

    public func teardown() async {
        chunks.removeAll()
        profile = nil
    }

    private func makeTSPacket(pid: UInt16, payload: Data) -> Data {
        var packet = Data(count: packetSize)
        packet[0] = 0x47
        packet[1] = UInt8((pid >> 8) & 0x1F)
        packet[2] = UInt8(pid & 0xFF)
        packet[3] = 0x10
        let copyCount = min(payload.count, 184)
        if copyCount > 0 {
            packet.replaceSubrange(4..<(4 + copyCount), with: payload.prefix(copyCount))
        }
        return packet
    }
}
