import Foundation

/// Ordering for the "Open With…" list: the default app first, then the rest
/// by name, with duplicates (the same app registered at two paths, or the
/// same path twice) removed.
public enum OpenWithApps {
    public struct Candidate: Equatable {
        public let name: String
        public let path: String
        public let bundleID: String?

        public init(name: String, path: String, bundleID: String?) {
            self.name = name
            self.path = path
            self.bundleID = bundleID
        }
    }

    public struct Entry: Equatable {
        public let app: Candidate
        public let isDefault: Bool
    }

    public static func order(_ candidates: [Candidate], defaultPath: String?) -> [Entry] {
        let normalizedDefault = defaultPath.map(normalize)
        let defaultApp = candidates.first { normalize($0.path) == normalizedDefault }
        var seenPaths = Set<String>()
        var seenBundles = Set<String>()
        var result: [Entry] = []
        func add(_ app: Candidate, isDefault: Bool) {
            let path = normalize(app.path)
            guard !seenPaths.contains(path) else { return }
            if let bundle = app.bundleID, seenBundles.contains(bundle) { return }
            seenPaths.insert(path)
            if let bundle = app.bundleID { seenBundles.insert(bundle) }
            result.append(Entry(app: app, isDefault: isDefault))
        }
        if let defaultApp { add(defaultApp, isDefault: true) }
        // Prefer copies in /Applications over other locations for the same app.
        let rest = candidates.sorted { a, b in
            let byName = a.name.localizedCaseInsensitiveCompare(b.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return rank(a.path) < rank(b.path)
        }
        for app in rest { add(app, isDefault: false) }
        return result
    }

    private static func normalize(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private static func rank(_ path: String) -> Int {
        if path.hasPrefix("/Applications/") { return 0 }
        if path.hasPrefix("/System/Applications/") { return 1 }
        return 2
    }
}
