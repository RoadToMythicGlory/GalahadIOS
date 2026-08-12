import Foundation
import MediaCore

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class BenchmarkViewModel: ObservableObject {
    @Published var environment = HostEnvironment.detectCurrent()
    @Published var pluginOK = false
    @Published var pluginDetail = "Not probed"
    @Published var log = ""
    @Published var lastReportPath: String?
    @Published var profileClassifications: [String: String] = [:]

    private let reportsDirectory: URL = {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("GalahadFeasibilityReports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func bootstrap() {
        environment = HostEnvironment.detectCurrent()
#if os(iOS)
        let model = UIDevice.current.model
        environment = HostEnvironment(
            osName: "iOS \(UIDevice.current.systemVersion)",
            arch: "arm64",
            hasXcode: false,
            hasPhysicaliPhone: !model.contains("Simulator"),
            notes: "Device model string: \(model). Confirm physical device before GO."
        )
#endif
        probePlugins()
        emitDeviceValidationRequired()
    }

    func classification(for profileID: String) -> String {
        profileClassifications[profileID] ?? ProfileClassification.inconclusive.rawValue
    }

    func probePlugins() {
        // Bridged C probe when the ObjC++ target is linked.
        #if GALAHAD_LINK_GST_BRIDGE
        var status = GalahadGSTPluginStatus()
        pluginOK = galahad_gst_probe_plugins(&status)
        pluginDetail = String(cString: status.detail)
        #else
        pluginOK = false
        pluginDetail = "GStreamer bridge not linked in this build configuration."
        #endif
        appendLog("plugin probe: ok=\(pluginOK) detail=\(pluginDetail)")
    }

    func runStubHarness() async {
        appendLog("Starting stub layered harness (not a device GO measurement)…")
        do {
            let profile = VideoProfile.gateCandidates[0]
            let generator = TestPatternGenerator(profile: profile)
            let coordinator = FeasibilityPipelineCoordinator()
            let encoder = StubHEVCEncoder()
            let normalizer = PassthroughFrameNormalizer(format: .i420)
            let muxer = FileMpegTsMuxer()
            let transport = RecordingSrtTransport(
                endpoint: SrtEndpoint(host: "127.0.0.1", port: 9001)
            )

            try await coordinator.start(
                profile: profile,
                encoder: encoder,
                normalizer: normalizer,
                muxer: muxer,
                transport: transport
            )

            for i in 0..<90 {
                try await coordinator.submitRawFrame(
                    raw: generator.frame(index: UInt64(i)),
                    width: profile.width,
                    height: profile.height,
                    inputFormat: .i420,
                    presentationTime: .milliseconds(Int64(i * 1000 / profile.frameRate))
                )
            }

            let metrics = await coordinator.snapshotMetrics()
            let sizes = await transport.observedPayloadSizes()
            let packetization = DefaultPacketizationVerifier().verify(observedPayloadSizes: sizes)
            await coordinator.stop()

            appendLog(
                String(
                    format: "stub metrics fps=%.2f bitrate=%.2fMbps encoderMs=%.2f e2eMs=%.2f pktOK=%@",
                    metrics.measuredFps,
                    metrics.bitrateMbps,
                    metrics.averageEncoderLatencyMs,
                    metrics.averageEndToEndLatencyMs,
                    String(packetization.matchesPreferred)
                )
            )
            appendLog("NOTE: stub encoder results are NOT device evidence and cannot produce GO.")
        } catch {
            appendLog("stub harness failed: \(error.localizedDescription)")
        }
    }

    func emitDeviceValidationRequired() {
        let report = DeviceValidationReportBuilder.buildScaffoldHostReport()
        for result in report.profileResults {
            profileClassifications[result.profileID] = result.classification.rawValue
        }
        do {
            let url = try write(report: report, filenamePrefix: "DEVICE_VALIDATION_REQUIRED")
            lastReportPath = url.path
            appendLog("Wrote \(url.lastPathComponent)")
            appendLog("VERDICT: \(report.decision.verdict.rawValue)")
        } catch {
            appendLog("failed to write report: \(error.localizedDescription)")
        }
    }

    func exportReport() {
        emitDeviceValidationRequired()
    }

    private func write(report: FeasibilityReport, filenamePrefix: String) throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: report.generatedAt).replacingOccurrences(of: ":", with: "-")
        let url = reportsDirectory.appendingPathComponent("\(filenamePrefix)_\(stamp).json")
        let json = try report.jsonString()
        try json.write(to: url, atomically: true, encoding: .utf8)

        // Also mirror into repo docs/reports when running on macOS desktop sandbox with access.
        #if os(macOS)
        if let repoReports = resolveRepoReportsDirectory() {
            let mirror = repoReports.appendingPathComponent(url.lastPathComponent)
            try? json.write(to: mirror, atomically: true, encoding: .utf8)
        }
        #endif
        return url
    }

    private func resolveRepoReportsDirectory() -> URL? {
        // Optional convenience for local Mac checkouts.
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("docs/reports"),
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private func appendLog(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        log = "[\(stamp)] \(line)\n" + log
    }
}
