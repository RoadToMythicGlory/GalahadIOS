import Foundation

public struct FeasibilityReport: Codable, Sendable, Equatable {
    public var reportVersion: String
    public var generatedAt: Date
    public var hostEnvironment: HostEnvironment
    public var toolchain: ToolchainInfo
    public var pluginRegistration: PluginRegistrationEvidence
    public var pixelFormats: [String]
    public var profileResults: [ProfileRunEvidence]
    public var packetization: PacketizationReport?
    public var licensingBlockers: [String]
    public var deploymentBlockers: [String]
    public var decision: GateDecision

    public init(
        reportVersion: String = "phase2-v1",
        generatedAt: Date = Date(),
        hostEnvironment: HostEnvironment,
        toolchain: ToolchainInfo,
        pluginRegistration: PluginRegistrationEvidence,
        pixelFormats: [String],
        profileResults: [ProfileRunEvidence],
        packetization: PacketizationReport?,
        licensingBlockers: [String],
        deploymentBlockers: [String],
        decision: GateDecision
    ) {
        self.reportVersion = reportVersion
        self.generatedAt = generatedAt
        self.hostEnvironment = hostEnvironment
        self.toolchain = toolchain
        self.pluginRegistration = pluginRegistration
        self.pixelFormats = pixelFormats
        self.profileResults = profileResults
        self.packetization = packetization
        self.licensingBlockers = licensingBlockers
        self.deploymentBlockers = deploymentBlockers
        self.decision = decision
    }

    public func jsonString(pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}

public struct HostEnvironment: Codable, Sendable, Equatable {
    public var osName: String
    public var arch: String
    public var hasXcode: Bool
    public var hasPhysicaliPhone: Bool
    public var notes: String

    public init(osName: String, arch: String, hasXcode: Bool, hasPhysicaliPhone: Bool, notes: String) {
        self.osName = osName
        self.arch = arch
        self.hasXcode = hasXcode
        self.hasPhysicaliPhone = hasPhysicaliPhone
        self.notes = notes
    }

    public static func detectCurrent() -> HostEnvironment {
        #if os(macOS)
        return HostEnvironment(
            osName: "macOS",
            arch: "apple-darwin",
            hasXcode: FileManager.default.fileExists(atPath: "/Applications/Xcode.app"),
            hasPhysicaliPhone: false,
            notes: "Physical iPhone attachment must be confirmed by the operator before GO."
        )
        #elseif os(iOS)
        return HostEnvironment(
            osName: "iOS",
            arch: "arm64",
            hasXcode: false,
            hasPhysicaliPhone: true,
            notes: "Running on device."
        )
        #else
        return HostEnvironment(
            osName: "Windows",
            arch: "x86_64",
            hasXcode: false,
            hasPhysicaliPhone: false,
            notes: "Scaffold/harness authoring host. arm64 iOS device validation cannot run here."
        )
        #endif
    }
}

public struct ToolchainInfo: Codable, Sendable, Equatable {
    public var swiftVersion: String
    public var xcodeVersion: String?
    public var gstreamerRecipe: String
    /// Product encode path (VideoToolbox HEVC); not a GStreamer encoder plugin.
    public var hevcEncoder: String?

    public init(
        swiftVersion: String,
        xcodeVersion: String? = nil,
        gstreamerRecipe: String,
        hevcEncoder: String? = nil
    ) {
        self.swiftVersion = swiftVersion
        self.xcodeVersion = xcodeVersion
        self.gstreamerRecipe = gstreamerRecipe
        self.hevcEncoder = hevcEncoder
    }
}

public struct PluginRegistrationEvidence: Codable, Sendable, Equatable {
    public var gstInitSucceeded: Bool
    public var registeredPlugins: [String]
    public var missingPlugins: [String]
    public var detail: String

    public init(
        gstInitSucceeded: Bool,
        registeredPlugins: [String],
        missingPlugins: [String],
        detail: String
    ) {
        self.gstInitSucceeded = gstInitSucceeded
        self.registeredPlugins = registeredPlugins
        self.missingPlugins = missingPlugins
        self.detail = detail
    }
}
