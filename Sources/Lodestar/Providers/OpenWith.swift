import AppKit
import LodestarCore

/// The "Open With…" action for launcher items that stand for files or
/// folders: a nested list in the ⌘K popover of the apps that can open them,
/// the default app first.
enum OpenWith {
    /// `urls` are opened together; the app list is for the first one.
    static func action(for urls: [URL]) -> LauncherAction {
        LauncherAction("Open With…", symbol: "arrow.up.right.square", shortcut: .openWith) {
            appActions(for: urls)
        }
    }

    static func appActions(for urls: [URL]) -> [LauncherAction] {
        guard let first = urls.first else { return [] }
        let workspace = NSWorkspace.shared
        let candidates = workspace.urlsForApplications(toOpen: first).map { app in
            OpenWithApps.Candidate(name: displayName(of: app), path: app.path, bundleID: Bundle(url: app)?.bundleIdentifier)
        }
        let defaultPath = workspace.urlForApplication(toOpen: first)?.path
        return OpenWithApps.order(candidates, defaultPath: defaultPath).map { entry in
            let app = URL(fileURLWithPath: entry.app.path)
            return LauncherAction(entry.app.name, symbol: "app", icon: .file(entry.app.path),
                                  badge: entry.isDefault ? "Default" : nil) {
                workspace.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                return .close
            }
        }
    }

    private static func displayName(of app: URL) -> String {
        let name = FileManager.default.displayName(atPath: app.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
