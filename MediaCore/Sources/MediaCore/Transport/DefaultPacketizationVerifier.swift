import Foundation

public struct DefaultPacketizationVerifier: PacketizationVerifier {
    public init() {}

    public func verify(observedPayloadSizes: [Int], preferred: Int = SrtEndpoint.preferredPayloadBytes) -> PacketizationReport {
        guard !observedPayloadSizes.isEmpty else {
            return PacketizationReport(
                preferredBytes: preferred,
                observedSizes: [],
                dominantSize: nil,
                matchesPreferred: false,
                notes: "No packets observed; cannot claim 1316-byte packetization."
            )
        }

        var counts: [Int: Int] = [:]
        for size in observedPayloadSizes {
            counts[size, default: 0] += 1
        }
        let dominant = counts.max(by: { $0.value < $1.value })?.key
        let preferredCount = counts[preferred, default: 0]
        let ratio = Double(preferredCount) / Double(observedPayloadSizes.count)
        // Accept when the majority of observed payloads match preferred packing.
        let matches = ratio >= 0.85

        let notes: String
        if matches {
            notes = String(
                format: "Observed %.1f%% payloads at %d bytes (7×188 MPEG-TS).",
                ratio * 100,
                preferred
            )
        } else if let dominant {
            notes = "Dominant payload size \(dominant) bytes; preferred \(preferred) not verified."
        } else {
            notes = "Unable to determine dominant payload size."
        }

        return PacketizationReport(
            preferredBytes: preferred,
            observedSizes: Array(Set(observedPayloadSizes)).sorted(),
            dominantSize: dominant,
            matchesPreferred: matches,
            notes: notes
        )
    }
}
