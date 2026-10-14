import AppKit

/// Finds installed applications by scanning the standard application
/// folders. (A Spotlight `kMDItemContentType == com.apple.application-bundle`
/// query would also work; a direct scan is predictable and needs no index.)
final class AppIndex {
    struct App: Hashable {
        let name: String
        let path: String
        let bundleID: String?
    }

    private(set) var apps: [App] = []
    private var lastScan: Date = .distantPast
    private let extraDirectories: [String]
    private let queue = DispatchQueue(label: "lodestar.appindex", qos: .userInitiated)

    init(extraDirectories: [String] = []) {
        self.extraDirectories = extraDirectories
    }

    var searchDirectories: [String] {
        ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
         "/System/Library/CoreServices/Applications", NSHomeDirectory() + "/Applications"]
            + extraDirectories.map { ($0 as NSString).expandingTildeInPath }
    }

    /// Rescans in the background if the index is older than `maxAge`.
    func refreshIfStale(maxAge: TimeInterval = 60, completion: (() -> Void)? = nil) {
        guard Date().timeIntervalSince(lastScan) > maxAge else { return }
        lastScan = Date()
        let dirs = searchDirectories
        queue.async {
            let found = AppIndex.scan(dirs)
            DispatchQueue.main.async {
                self.apps = found
                completion?()
            }
        }
    }

    static func scan(_ directories: [String]) -> [App] {
        let fm = FileManager.default
        var seen = Set<String>()
        var result: [App] = []
        func visit(_ dir: String, depth: Int) {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for entry in entries {
                let path = (dir as NSString).appendingPathComponent(entry)
                if entry.hasSuffix(".app") {
                    let resolved = (path as NSString).resolvingSymlinksInPath
                    guard seen.insert(resolved).inserted else { continue }
                    let bundle = Bundle(path: path)
                    let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (entry as NSString).deletingPathExtension
                    result.append(App(name: name, path: path, bundleID: bundle?.bundleIdentifier))
                } else if depth < 2 {
                    var isDir: ObjCBool = false
                    // Descend into plain folders like /Applications/Adobe Foo/
                    if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue, !entry.hasPrefix(".") {
                        visit(path, depth: depth + 1)
                    }
                }
            }
        }
        for dir in directories { visit(dir, depth: 0) }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
