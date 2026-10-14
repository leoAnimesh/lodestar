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
