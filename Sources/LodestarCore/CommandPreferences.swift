import Foundation

/// Per-command user settings stored under `"commands"` in config.json, keyed
/// by command ID (for example `"cmd:clipboard"` or `"script:/path/to/x.sh"`).
/// Every field is optional; a missing field means "use the default".
public struct CommandSettings: Codable, Equatable, Sendable {
    /// `false` hides the command from search. Missing means enabled.
    public var enabled: Bool?
    /// A short word that, typed exactly, puts this command first.
    public var alias: String?
    /// A global shortcut in config format, e.g. "ctrl+option+left".
    public var hotkey: String?

    public init(enabled: Bool? = nil, alias: String? = nil, hotkey: String? = nil) {
        self.enabled = enabled
        self.alias = alias
        self.hotkey = hotkey
    }

    public var isDefault: Bool { (enabled ?? true) && alias == nil && hotkey == nil }
}

public enum AliasError: Error, Equatable, Sendable, LocalizedError {
    case tooLong(max: Int)
    case containsWhitespace
    case inUse(byCommandID: String)

    public var errorDescription: String? {
        switch self {
        case .tooLong(let max): return "Aliases can be at most \(max) characters."
        case .containsWhitespace: return "Aliases can't contain spaces."
        case .inUse: return "Another command already uses this alias."
        }
    }
}

public enum CommandHotkeyError: Error, Equatable, Sendable, LocalizedError {
    case sameAsLauncher
    case inUse(byCommandID: String)

    public var errorDescription: String? {
        switch self {
        case .sameAsLauncher: return "That's the shortcut that opens Lodestar."
        case .inUse: return "Another command already uses this shortcut."
        }
    }
}

/// The enable/alias/hotkey model for all commands. Pure value type: the app
/// loads it from `LodestarConfig.commands`, mutates it, and saves it back.
/// Entries that return to their defaults are dropped, so config.json only
/// holds what the user actually changed.
public struct CommandPreferences: Equatable, Sendable {
    public private(set) var entries: [String: CommandSettings]

    public static let maxAliasLength = 24

    /// ID prefixes of commands that no longer exist ("wm:" window layouts).
    /// Their saved settings are ignored, so an old shortcut isn't registered
    /// for nothing, and are dropped the next time preferences are saved.
    public static let retiredIDPrefixes = ["wm:"]

    public init(_ entries: [String: CommandSettings]? = nil) {
        self.entries = (entries ?? [:]).filter { id, settings in
            !settings.isDefault && !CommandPreferences.retiredIDPrefixes.contains { id.hasPrefix($0) }
        }
    }

    /// The value to store in `LodestarConfig.commands` (nil when empty).
    public var configValue: [String: CommandSettings]? { entries.isEmpty ? nil : entries }

    public func settings(for id: String) -> CommandSettings { entries[id] ?? CommandSettings() }

    private mutating func edit(_ id: String, _ change: (inout CommandSettings) -> Void) {
        var s = settings(for: id)
        change(&s)
        entries[id] = s.isDefault ? nil : s
    }

    // MARK: Enabled

    public func isEnabled(_ id: String) -> Bool { entries[id]?.enabled ?? true }

    public mutating func setEnabled(_ enabled: Bool, for id: String) {
        edit(id) { $0.enabled = enabled ? nil : false }
    }

    /// Keeps the elements whose ID is enabled, preserving order.
    public func enabledOnly<T>(_ items: [T], id: (T) -> String) -> [T] {
        items.filter { isEnabled(id($0)) }
    }

    // MARK: Aliases

    /// Trims and lowercases an alias. Empty input means "no alias".
    public static func normalizeAlias(_ raw: String?) throws -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return nil }
        if trimmed.contains(where: { $0.isWhitespace }) { throw AliasError.containsWhitespace }
        if trimmed.count > maxAliasLength { throw AliasError.tooLong(max: maxAliasLength) }
        return trimmed
    }

    public func alias(for id: String) -> String? { entries[id]?.alias }

    /// Sets (or clears, for nil/empty) the alias. Throws if it's malformed or
    /// another command already uses it.
    public mutating func setAlias(_ raw: String?, for id: String) throws {
        let alias = try CommandPreferences.normalizeAlias(raw)
        if let alias, let owner = commandID(forAlias: alias), owner != id {
            throw AliasError.inUse(byCommandID: owner)
        }
        edit(id) { $0.alias = alias }
    }

    /// The enabled command whose alias equals `query` (case-insensitive, trimmed).
    public func commandID(forAlias query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }
        return entries.first { $0.value.alias == q && ($0.value.enabled ?? true) }?.key
    }

    /// Reorders result IDs so an exact alias match comes first. The aliased
    /// command is inserted if it wasn't among the results; `available`
    /// says which IDs exist (and are enabled) right now.
    public func promotingAlias(of query: String, in ids: [String], available: Set<String>) -> [String] {
        guard let id = commandID(forAlias: query), available.contains(id) else { return ids }
        return [id] + ids.filter { $0 != id }
    }

    // MARK: Hotkeys

    public func hotkey(for id: String) -> HotkeySpec? { entries[id]?.hotkey.flatMap(HotkeySpec.init) }

    /// Sets (or clears, for nil) a command's global shortcut. Throws if it
    /// equals the launcher shortcut or another command's shortcut.
    public mutating func setHotkey(_ spec: HotkeySpec?, for id: String, launcherHotkey: HotkeySpec) throws {
        if let spec {
            if spec.isSameShortcut(as: launcherHotkey) { throw CommandHotkeyError.sameAsLauncher }
            if let owner = commandID(forHotkey: spec), owner != id { throw CommandHotkeyError.inUse(byCommandID: owner) }
        }
        edit(id) { $0.hotkey = spec?.configString }
    }

    public func commandID(forHotkey spec: HotkeySpec) -> String? {
        entries.keys.sorted().first { hotkey(for: $0)?.isSameShortcut(as: spec) == true }
    }

    /// Shortcuts to register: enabled commands with a valid hotkey, sorted by ID.
    public var hotkeyBindings: [(id: String, spec: HotkeySpec)] {
        entries.keys.sorted().compactMap { id in
            guard isEnabled(id), let spec = hotkey(for: id) else { return nil }
            return (id, spec)
        }
    }

    /// Forgets settings for commands that no longer exist (e.g. a deleted
    /// script). Returns the IDs removed.
    @discardableResult
    public mutating func prune(keeping existing: Set<String>) -> [String] {
        let gone = entries.keys.filter { !existing.contains($0) }.sorted()
        for id in gone { entries[id] = nil }
        return gone
    }
}

// MARK: - Command catalog (the Settings › Extensions list)

public enum CommandKind: String, CaseIterable, Sendable {
    case command, system, script, `extension`

    public var displayName: String {
        switch self {
        case .command: return "Command"
        case .system: return "System"
        case .script: return "Script"
        case .extension: return "Extension"
        }
    }
}

/// A searchable description of one command, independent of how it runs.
public struct CommandDescriptor: Equatable, Sendable, Identifiable {
    public let id: String
    public var title: String
    public var subtitle: String?
    public var kind: CommandKind
    /// Section in the list, e.g. "Lodestar", "System" or an extension's title.
    public var group: String
    public var keywords: [String]

    public init(id: String, title: String, subtitle: String? = nil, kind: CommandKind, group: String, keywords: [String] = []) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.group = group
        self.keywords = keywords
    }
}

public enum CommandCatalog {
    public struct Section: Equatable, Sendable {
        public let title: String
        public let commands: [CommandDescriptor]
    }

    /// Filters by kind and fuzzy query (title, group, keywords, alias), then
    /// groups into sections that keep the input's first-seen group order.
    /// With a query, commands inside a section are ordered by match quality.
    public static func sections(_ all: [CommandDescriptor], query: String, kind: CommandKind? = nil,
                                preferences: CommandPreferences = CommandPreferences()) -> [Section] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var scored: [(CommandDescriptor, Double)] = []
        for d in all where kind == nil || d.kind == kind {
            if q.isEmpty { scored.append((d, 0)); continue }
            var keys = d.keywords + [d.group, d.kind.displayName]
            if let alias = preferences.alias(for: d.id) { keys.append(alias) }
            if let m = FuzzyMatcher.bestMatch(q, title: d.title, keywords: keys) { scored.append((d, m.score)) }
        }
        var order: [String] = []
        var groups: [String: [(CommandDescriptor, Double)]] = [:]
        for entry in scored {
            if groups[entry.0.group] == nil { order.append(entry.0.group) }
            groups[entry.0.group, default: []].append(entry)
        }
        return order.map { title in
            var rows = groups[title] ?? []
            if !q.isEmpty { rows.sort { $0.1 > $1.1 } }  // stable on equal scores in practice
            return Section(title: title, commands: rows.map(\.0))
        }
    }
}
