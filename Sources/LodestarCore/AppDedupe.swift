import Foundation

/// An application bundle found by a scan, before duplicates are removed.
public struct AppCandidate: Hashable {
    public let name: String
    /// Path as found during the scan (may be a symlink/alias).
    public let path: String
    /// `path` with symlinks resolved and standardized.
    public let resolvedPath: String
    public let bundleID: String?
    public let version: String?
    /// True for apps macOS marks `LSDefaultSystemHidden`. Several of these
    /// share one localized display name (Siri.app and Siri AI.app both show
    /// as "Siri"), so they are also deduplicated by name.
    public let isSystemHidden: Bool

    public init(name: String, path: String, resolvedPath: String? = nil, bundleID: String? = nil,
                version: String? = nil, isSystemHidden: Bool = false) {
        self.name = name
        self.path = path
        self.resolvedPath = resolvedPath ?? AppDedupe.canonical(path)
        self.bundleID = bundleID
        self.version = version
        self.isSystemHidden = isSystemHidden
    }

    /// The scanned path is a symlink (or reaches the bundle through one).
    public var isAlias: Bool { AppDedupe.standardize(path) != resolvedPath }
}

public enum AppDedupe {
    public static func standardize(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    public static func canonical(_ path: String) -> String {
        ((path as NSString).resolvingSymlinksInPath as NSString).standardizingPath
    }

    /// Keeps one app per bundle identifier (or per resolved path when there is
    /// no identifier), and one per display name among system-hidden apps. Order of the
    /// first occurrence of each app is preserved.
    ///
    /// Winner order: newer version, then /Applications-style locations over
    /// /System, then a real bundle over an alias, then the shorter path.
    public static func dedupe(_ candidates: [AppCandidate]) -> [AppCandidate] {
        var order: [String] = []
        var best: [String: AppCandidate] = [:]
        for c in candidates {
            let key: String
            if c.isSystemHidden {
                key = "hidden:" + c.name.lowercased()
            } else {
                key = c.bundleID.flatMap { $0.isEmpty ? nil : "id:" + $0.lowercased() } ?? "path:" + c.resolvedPath
            }
            if let current = best[key] {
                if isPreferred(c, over: current) { best[key] = c }
            } else {
                best[key] = c
                order.append(key)
            }
        }
        return order.compactMap { best[$0] }
    }

    static func isPreferred(_ a: AppCandidate, over b: AppCandidate) -> Bool {
        let v = compareVersions(a.version, b.version)
        if v != 0 { return v > 0 }
        let la = locationRank(a), lb = locationRank(b)
        if la != lb { return la < lb }
        if a.isAlias != b.isAlias { return !a.isAlias }
        if a.path.count != b.path.count { return a.path.count < b.path.count }
        return a.path < b.path
    }

    /// Lower is better. User/`/Applications` installs beat system copies.
    static func locationRank(_ c: AppCandidate) -> Int {
        let p = c.resolvedPath
        if p.hasPrefix("/System/") { return 2 }
        return 0
    }

    /// Numeric, dot-separated comparison. Returns 1, 0 or -1; a missing
    /// version never beats a present one.
    public static func compareVersions(_ a: String?, _ b: String?) -> Int {
        switch (a, b) {
        case (nil, nil): return 0
        case (_?, nil): return 1
        case (nil, _?): return -1
        case let (a?, b?):
            let x = a.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
            let y = b.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
            for i in 0..<max(x.count, y.count) {
                let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
                if l != r { return l > r ? 1 : -1 }
            }
            return 0
        }
    }
}
