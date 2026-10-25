import Foundation

public enum InstallProblem: Error, Equatable, CustomStringConvertible {
    case notAnAppBundle
    case translocated
    case developmentBuild
    case readOnlyVolume
    case notWritable

    public var description: String {
        switch self {
        case .notAnAppBundle:
            return "Lodestar isn't running from an app bundle (for example with swift run), so it can't update itself."
        case .translocated:
            return "macOS is running Lodestar from a temporary read-only location. Move Lodestar to your Applications folder, open it from there, and try again."
        case .developmentBuild:
            return "This is a development build inside its source folder; rebuild it with ./scripts/bundle.sh instead."
        case .readOnlyVolume:
            return "Lodestar is on a read-only disk, so it can't be replaced."
        case .notWritable:
            return "You don't have permission to replace Lodestar where it is installed."
        }
    }
}

public enum BundleValidationError: Error, Equatable, CustomStringConvertible {
    case missingApp
    case multipleApps
    case unreadableInfo
    case wrongBundleIdentifier(String?)
    case wrongVersion(expected: String, found: String?)

    public var description: String {
        switch self {
        case .missingApp: return "The download doesn't contain Lodestar.app."
        case .multipleApps: return "The download contains more than one app."
        case .unreadableInfo: return "The downloaded app's Info.plist can't be read."
        case .wrongBundleIdentifier(let id): return "The downloaded app isn't Lodestar (bundle ID \(id ?? "missing"))."
        case .wrongVersion(let expected, let found):
            return "The downloaded app reports version \(found ?? "none"), but \(expected) was expected."
        }
    }
}

public enum ReplaceError: Error, Equatable, CustomStringConvertible {
    case moveAsideFailed(String)
    /// The new app couldn't be moved in; the old one was put back.
    case installFailedRestored(String)
    /// The new app couldn't be moved in and the old one couldn't be put back;
    /// it is at `backup`.
    case installFailedBackupAt(String, backup: String)

    public var description: String {
        switch self {
        case .moveAsideFailed(let reason): return "Couldn't move the current version aside: \(reason)"
        case .installFailedRestored(let reason): return "Couldn't install the new version (\(reason)). Your current version is unchanged."
        case .installFailedBackupAt(let reason, let backup):
            return "Couldn't install the new version (\(reason)). Your previous version is at \(backup)."
        }
    }
}

/// Checks where Lodestar is installed, validates a downloaded bundle, and
/// swaps it in. Foundation only, so it can be unit tested with fake bundles.
public struct AppReplacer {
    public typealias Mover = (URL, URL) throws -> Void

    let fileManager: FileManager
    let move: Mover

    public init(fileManager: FileManager = .default, move: Mover? = nil) {
        self.fileManager = fileManager
        self.move = move ?? { try FileManager.default.moveItem(at: $0, to: $1) }
    }

    // MARK: Install location

    /// Why the app at `appURL` can't be replaced in place, or nil if it can.
    public func installProblem(for appURL: URL) -> InstallProblem? {
        let path = appURL.standardizedFileURL.path
        guard appURL.pathExtension.lowercased() == "app", isDirectory(appURL) else { return .notAnAppBundle }
        let resolved = appURL.resolvingSymlinksInPath().path
        if path.contains("/AppTranslocation/") || resolved.contains("/AppTranslocation/") { return .translocated }
        if Self.isDevelopmentBuild(appURL) { return .developmentBuild }
        if Self.isReadOnlyVolume(path) { return .readOnlyVolume }
        let parent = appURL.deletingLastPathComponent().path
        guard fileManager.isWritableFile(atPath: parent), fileManager.isWritableFile(atPath: path) else { return .notWritable }
        return nil
    }

    /// A `.build` folder anywhere in the path, or `<repo>/build/Lodestar.app`
    /// next to a `Package.swift`: replacing those would fight the developer's
    /// own build.
    public static func isDevelopmentBuild(_ appURL: URL) -> Bool {
        let components = appURL.standardizedFileURL.pathComponents
        if components.contains(".build") { return true }
        let repo = appURL.deletingLastPathComponent().deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: repo.appendingPathComponent("Package.swift").path)
    }

    static func isReadOnlyVolume(_ path: String) -> Bool {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return true }
        return (info.f_flags & UInt32(MNT_RDONLY)) != 0
    }

    // MARK: Validation

    /// The single `.app` directly inside `directory` (what `ditto -x -k`
    /// produces from a `--keepParent` archive). Symlinks don't count.
    public func findApp(in directory: URL) throws -> URL {
        let entries = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        let apps = entries.filter { url in
            url.pathExtension.lowercased() == "app"
                && (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
                && isDirectory(url)
        }
        guard !apps.isEmpty else { throw BundleValidationError.missingApp }
        guard apps.count == 1 else { throw BundleValidationError.multipleApps }
        return apps[0]
    }

    /// Bundle ID and version of `app` must match.
    public func validate(app: URL, bundleIdentifier: String, version: SemanticVersion) throws {
        guard let info = Self.info(of: app) else { throw BundleValidationError.unreadableInfo }
        let id = info["CFBundleIdentifier"] as? String
        guard id == bundleIdentifier else { throw BundleValidationError.wrongBundleIdentifier(id) }
        let found = info["CFBundleShortVersionString"] as? String
        guard let parsed = found.flatMap(SemanticVersion.init), parsed == version else {
            throw BundleValidationError.wrongVersion(expected: version.description, found: found)
        }
    }

    public static func info(of app: URL) -> [String: Any]? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    // MARK: Replace

    /// Swaps `newApp` in at `currentApp`:
    ///   1. move the current app into `backupDirectory` (same volume, so a rename),
    ///   2. move the new app to the original path,
    ///   3. if step 2 fails, move the old app back.
    /// Returns the backup's location; the caller trashes it once the swap
    /// succeeded. The original path is never left empty unless both the
    /// install and the restore fail, and then the error says where the
    /// previous version is.
    @discardableResult
    public func replace(currentApp: URL, with newApp: URL, backupDirectory: URL) throws -> URL {
        let backup = backupDirectory.appendingPathComponent("previous-" + currentApp.lastPathComponent)
        do {
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            try move(currentApp, backup)
        } catch {
            throw ReplaceError.moveAsideFailed(error.localizedDescription)
        }
        do {
            try move(newApp, currentApp)
        } catch {
            let reason = error.localizedDescription
            if (try? move(backup, currentApp)) != nil { throw ReplaceError.installFailedRestored(reason) }
            throw ReplaceError.installFailedBackupAt(reason, backup: backup.path)
        }
        return backup
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
