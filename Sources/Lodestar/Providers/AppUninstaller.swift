import AppKit
import LodestarCore

/// "Uninstall Application": confirms, quits the app if it is running, then
/// moves the bundle (and optionally its support files) to the Trash. Nothing
/// is ever deleted outright, so it can be undone from the Trash.
enum AppUninstaller {
    /// `onRemoved` runs after the app is in the Trash, so the index can drop it.
    static func action(for app: AppIndex.App, onRemoved: @escaping () -> Void = {}) -> LauncherAction? {
        guard !AppUninstall.isProtected(path: app.path, bundleID: app.bundleID),
              app.bundleID != Bundle.main.bundleIdentifier else { return nil }
        return LauncherAction("Uninstall Application", symbol: "trash", shortcut: .uninstall,
                              isDestructive: true, startsSection: true) {
            uninstall(app, onRemoved: onRemoved)
        }
    }

    private static func uninstall(_ app: AppIndex.App, onRemoved: @escaping () -> Void) -> ActionOutcome {
        let fm = FileManager.default
        let related = AppUninstall.relatedPaths(bundleID: app.bundleID, name: app.name, home: NSHomeDirectory())
            .filter { fm.fileExists(atPath: $0) }
        let running = app.bundleID.map { NSRunningApplication.runningApplications(withBundleIdentifier: $0) } ?? []

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall \(app.name)?"
        var info = "\(app.name) will be moved to the Trash."
        if !running.isEmpty { info += " It is running and will be quit first." }
        if !related.isEmpty {
            let home = NSHomeDirectory()
            info += "\n\nRelated files found:\n" + related.map { "• " + $0.replacingOccurrences(of: home, with: "~") }.joined(separator: "\n")
        }
        alert.informativeText = info
        let alsoRelated = NSButton(checkboxWithTitle: "Also move related files to the Trash", target: nil, action: nil)
        alsoRelated.state = .on
        if !related.isEmpty {
            alsoRelated.sizeToFit()
            alert.accessoryView = alsoRelated
        }
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return .stay }

        if !running.isEmpty {
            running.forEach { $0.terminate() }
            let deadline = Date().addingTimeInterval(5)
            while running.contains(where: { !$0.isTerminated }) && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            if running.contains(where: { !$0.isTerminated }) {
                return .toast("\(app.name) did not quit. Quit it and try again")
            }
        }

        // A symlinked app (e.g. /Applications/Foo.app -> ~/Apps/Foo.app):
        // trash the real bundle, then the link it leaves dangling.
        let realPath = AppUninstall.resolvedPath(app.path)
        if let failure = trash(realPath) { return .toast(failure) }
        if realPath != app.path { _ = try? fm.trashItem(at: URL(fileURLWithPath: app.path), resultingItemURL: nil) }
        onRemoved()

        var leftOver = 0
        if !related.isEmpty, alsoRelated.state == .on {
            for path in related {
                do { try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil) } catch { leftOver += 1 }
            }
        }
        let message = leftOver == 0 ? "Moved \(app.name) to the Trash"
            : "Moved \(app.name) to the Trash; \(leftOver) related \(leftOver == 1 ? "item" : "items") couldn't be moved"
        return .closeThen { HUD.show(message, symbol: "trash", duration: leftOver == 0 ? 1.6 : 3) }
    }

    /// Returns an error message, or nil on success. Falls back to Finder
    /// (which asks for an administrator password) for root-owned apps.
    private static func trash(_ path: String) -> String? {
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            return nil
        } catch {
            let escaped = path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let result = SystemActions.runAppleScript("tell application \"Finder\" to delete POSIX file \"\(escaped)\"")
            if result != nil { return nil }
            return "Couldn't uninstall: \(error.localizedDescription)"
        }
    }
}
