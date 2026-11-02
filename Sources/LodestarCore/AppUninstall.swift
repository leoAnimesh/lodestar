import Foundation

/// Pure helpers for "Uninstall Application": which apps may be removed and
/// which per-user support files usually belong to one.
public enum AppUninstall {
    /// Apps that ship with macOS (or live on the sealed system volume) can't
    /// be removed, so the action is not offered for them.
    public static func isProtected(path: String, bundleID: String?) -> Bool {
        // Apple apps installed by the user (Xcode, Pages...) live in
        // /Applications and can be removed; the OS ones are on the sealed volume.
        // Some OS apps only *look* user-installed: /Applications/Safari.app is a
        // symlink into /System/Cryptexes, so check where the path really goes.
        let systemRoots = ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/"]
        return [path, resolvedPath(path)].contains { p in systemRoots.contains { p.hasPrefix($0) } }
    }

    /// The real location of an app bundle, following symlinks.
    public static func resolvedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// Whether `component` can be used as one path component under Library:
    /// a crafted bundle ID or name such as ".." must never point the cleanup
    /// at ~/Library itself or anywhere outside it.
    public static func isSafePathComponent(_ component: String) -> Bool {
        !component.isEmpty && component != "." && component != ".." && !component.contains("/")
            && !component.contains("\0")
    }

    /// Candidate support-file locations for an app, in the user's Library.
    /// Callers keep only the ones that exist.
    public static func relatedPaths(bundleID: String?, name: String, home: String) -> [String] {
        let lib = home + "/Library"
        var paths: [String] = []
        if let id = bundleID, isSafePathComponent(id) {
            paths += [
                "\(lib)/Application Support/\(id)",
                "\(lib)/Caches/\(id)",
                "\(lib)/Preferences/\(id).plist",
                "\(lib)/Containers/\(id)",
                "\(lib)/Saved Application State/\(id).savedState",
                "\(lib)/HTTPStorages/\(id)",
                "\(lib)/WebKit/\(id)",
                "\(lib)/Logs/\(id)",
            ]
        }
        if isSafePathComponent(name) {
            paths += [
                "\(lib)/Application Support/\(name)",
                "\(lib)/Caches/\(name)",
                "\(lib)/Logs/\(name)",
            ]
        }
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}
