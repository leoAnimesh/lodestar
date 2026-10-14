import Foundation

/// User configuration, read from ~/.config/lodestar/config.json.
public struct LodestarConfig: Codable, Equatable, Sendable {
    /// Global shortcut, e.g. "option+space" or "cmd+shift+space".
    public var hotkey: String?
    /// Extra directories to scan for .app bundles.
    public var appDirectories: [String]?
    /// Maximum clipboard history entries kept on disk.
    public var clipboardHistoryLimit: Int?
    /// Set false to disable clipboard history entirely.
    public var clipboardHistoryEnabled: Bool?

    public init(hotkey: String? = nil, appDirectories: [String]? = nil, clipboardHistoryLimit: Int? = nil, clipboardHistoryEnabled: Bool? = nil) {
        self.hotkey = hotkey
        self.appDirectories = appDirectories
        self.clipboardHistoryLimit = clipboardHistoryLimit
        self.clipboardHistoryEnabled = clipboardHistoryEnabled
    }

    public static func load(from url: URL) -> LodestarConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(LodestarConfig.self, from: data) else {
            return LodestarConfig()
        }
        return config
    }

    /// Keys this type owns in config.json. Any other keys are left untouched on save.
    static let knownKeys = ["hotkey", "appDirectories", "clipboardHistoryLimit", "clipboardHistoryEnabled"]

    /// Reads the config at `url`, applies `change`, and writes it back atomically.
    /// Unknown keys are preserved. If the file exists but can't be parsed, nothing
    /// is written and `ConfigError.invalidFile` is thrown, so a typo in a
    /// hand-edited file is never silently overwritten.
    @discardableResult
    public static func update(at url: URL, _ change: (inout LodestarConfig) -> Void) throws -> LodestarConfig {
        let existing = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
        let (data, config) = try updated(existing, change)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return config
    }

    /// Pure core of `update(at:_:)`: returns the new file contents and the resulting config.
    public static func updated(_ existing: Data?, _ change: (inout LodestarConfig) -> Void) throws -> (Data, LodestarConfig) {
        var object: [String: Any] = [:]
        var config = LodestarConfig()
        if let existing, !existing.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            guard let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: Any],
                  let decoded = try? JSONDecoder().decode(LodestarConfig.self, from: existing) else {
                throw ConfigError.invalidFile
            }
            object = parsed
            config = decoded
        }
        change(&config)
        for key in knownKeys { object[key] = nil }
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any] ?? [:]
        object.merge(encoded) { _, new in new }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return (data + Data("\n".utf8), config)
    }
}

public enum ConfigError: Error, LocalizedError, Equatable {
    case invalidFile

    public var errorDescription: String? {
        switch self {
        case .invalidFile: return "config.json isn't valid. Fix or remove it, then try again."
        }
    }
}

public enum LodestarPaths {
    /// ~/.config/lodestar — user-editable config, scripts and extensions.
    public static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/lodestar", isDirectory: true)
    }
    public static var configFile: URL { configDirectory.appendingPathComponent("config.json") }
    public static var scriptsDirectory: URL { configDirectory.appendingPathComponent("scripts", isDirectory: true) }
    public static var extensionsDirectory: URL { configDirectory.appendingPathComponent("extensions", isDirectory: true) }

    /// ~/Library/Application Support/Lodestar — app-managed state.
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Lodestar", isDirectory: true)
    }
}
