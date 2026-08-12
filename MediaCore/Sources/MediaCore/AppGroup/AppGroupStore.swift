import Foundation

/// Shared config/status between host app and Broadcast Upload Extension.
/// Falls back to in-memory storage when the App Group suite is unavailable
/// (unit tests / non-entitled SPM runs).
public actor AppGroupStore {
    public static let shared = AppGroupStore()

    private let suiteName: String
    private var memoryConfig: ClientConfig?
    private var memoryStatus: StreamStatus?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(suiteName: String = AppGroupConstants.identifier) {
        self.suiteName = suiteName
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    private var containerURL: URL? {
        #if canImport(Darwin)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
        #else
        nil // App Group containers are an Apple-platform concept (Linux CI runs in-memory)
        #endif
    }

    public func loadConfig() -> ClientConfig {
        if let data = readData(fileName: AppGroupConstants.configFileName, defaultsKey: AppGroupConstants.configDefaultsKey),
           let config = try? decoder.decode(ClientConfig.self, from: data) {
            memoryConfig = config
            return config
        }
        if let memoryConfig { return memoryConfig }
        let fresh = ClientConfig()
        memoryConfig = fresh
        return fresh
    }

    public func saveConfig(_ config: ClientConfig) throws {
        let data = try encoder.encode(config)
        memoryConfig = config
        try writeData(data, fileName: AppGroupConstants.configFileName, defaultsKey: AppGroupConstants.configDefaultsKey)
    }

    public func loadStatus() -> StreamStatus {
        if let data = readData(fileName: AppGroupConstants.statusFileName, defaultsKey: AppGroupConstants.statusDefaultsKey),
           let status = try? decoder.decode(StreamStatus.self, from: data) {
            memoryStatus = status
            return status
        }
        return memoryStatus ?? StreamStatus()
    }

    public func saveStatus(_ status: StreamStatus) throws {
        let data = try encoder.encode(status)
        memoryStatus = status
        try writeData(data, fileName: AppGroupConstants.statusFileName, defaultsKey: AppGroupConstants.statusDefaultsKey)
    }

    /// True when App Group container or suite defaults are usable.
    public var isAppGroupAvailable: Bool {
        defaults != nil || containerURL != nil
    }

    private func readData(fileName: String, defaultsKey: String) -> Data? {
        if let url = containerURL?.appendingPathComponent(fileName),
           let data = try? Data(contentsOf: url) {
            return data
        }
        if let defaults, let data = defaults.data(forKey: defaultsKey) {
            return data
        }
        return nil
    }

    private func writeData(_ data: Data, fileName: String, defaultsKey: String) throws {
        var wrote = false
        if let url = containerURL?.appendingPathComponent(fileName) {
            try data.write(to: url, options: .atomic)
            wrote = true
        }
        if let defaults {
            defaults.set(data, forKey: defaultsKey)
            wrote = true
        }
        // In-memory already updated by callers; silent success when suite missing.
        _ = wrote
    }
}
