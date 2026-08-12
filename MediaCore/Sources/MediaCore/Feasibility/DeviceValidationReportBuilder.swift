import Foundation

/// Builds the Phase 2 report. Never invents measurements.
public enum DeviceValidationReportBuilder {
    public static func buildScaffoldHostReport() -> FeasibilityReport {
        let env = HostEnvironment.detectCurrent()
        let results = VideoProfile.gateCandidates.map { profile in
            ProfileRunEvidence(
                profileID: profile.id,
                deviceModel: "none",
                classification: .inconclusive,
                notes: "Not executed on a physical iPhone. DEVICE VALIDATION REQUIRED."
            )
        }

        let decision = GateDecision(
            verdict: .deviceValidationRequired,
            reason: "DEVICE VALIDATION REQUIRED — no macOS + physical iPhone evidence in this environment.",
            viableProfiles: []
        )

        return FeasibilityReport(
            hostEnvironment: env,
            toolchain: ToolchainInfo(
                swiftVersion: "5.10+",
                xcodeVersion: nil,
                gstreamerRecipe: "Scripts/build-gstreamer-ios.sh",
                hevcEncoder: "VideoToolbox VTCompressionSession HEVC (not validated on device)"
            ),
            pluginRegistration: PluginRegistrationEvidence(
                gstInitSucceeded: false,
                registeredPlugins: [],
                missingPlugins: [
                    "coreelements",
                    "app",
                    "videoconvert",
                    "videoscale",
                    "mpegtsmux",
                    "srtsink",
                    "audioconvert",
                    "atenc",
                ],
                detail: "GStreamer static registration was not executed on arm64 iOS. Encode is VideoToolbox HEVC, not a GStreamer video encoder."
            ),
            pixelFormats: PixelFormat.allCases.map(\.rawValue),
            profileResults: results,
            packetization: PacketizationReport(
                preferredBytes: SrtEndpoint.preferredPayloadBytes,
                observedSizes: [],
                dominantSize: nil,
                matchesPreferred: false,
                notes: "No packets observed on device; 1316-byte packetization not verified."
            ),
            licensingBlockers: [
                "GStreamer and libsrt licenses must be inventoried after first successful iOS link.",
            ],
            deploymentBlockers: [
                "No arm64 iOS binary produced in this environment.",
                "App Store / ReplayKit / signing validation deferred until post-GO phases.",
                "Binary size unknown until custom XCFramework is built on macOS.",
                "HEVC sustainment (thermal/fps/bitrate) not yet measured on device.",
            ],
            decision: decision
        )
    }
}
