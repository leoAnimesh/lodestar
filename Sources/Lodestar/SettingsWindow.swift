import AppKit
import SwiftUI
import LodestarCore

/// What the settings and onboarding screens need from the running app.
protocol SettingsHost: AnyObject {
    var currentHotkey: HotkeySpec { get }
    /// Registers `spec` as the launcher shortcut and saves it. Throws, leaving
    /// the previous shortcut active and the config unchanged, if either fails.
    func applyHotkey(_ spec: HotkeySpec) throws
    /// Releases every global shortcut while a recorder is capturing.
    func setHotkeysSuspended(_ suspended: Bool)
    /// Checks that a command shortcut can be registered (and registers it).
    func registerCommandHotkey(_ spec: HotkeySpec?, for id: String) throws
    /// Applies a freshly saved config live (appearance, menu bar, clipboard, commands...).
    func configDidChange(_ config: LodestarConfig)
    func commandCatalog() -> [RootScreen.CatalogEntry]
    func reloadExtensions()
    func clipboardEntryCount() -> Int
    func clearClipboardHistory()
    func showLauncher()
    func showOnboarding()
    func openSettings(tab: SettingsTab?)
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, extensions, clipboard, windows, advanced, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .extensions: return "Extensions"
        case .clipboard: return "Clipboard"
        case .windows: return "Windows"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .extensions: return "puzzlepiece.extension"
        case .clipboard: return "doc.on.clipboard"
        case .windows: return "macwindow.on.rectangle"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}

/// State and actions shared by the Settings window and the onboarding flow.
final class SettingsModel: ObservableObject {
    static let launcherTarget = "launcher"

    @Published var selectedTab: SettingsTab = .general
    @Published private(set) var hotkey: HotkeySpec

    @Published private(set) var launchAtLogin = LaunchAtLogin.State.disabled
    @Published var launchAtLoginError: String?

    @Published private(set) var config = LodestarConfig()
    @Published var configError: String?

    @Published private(set) var catalog: [RootScreen.CatalogEntry] = []
    @Published private(set) var clipboardCount = 0
    /// Per-command alias validation messages.
    @Published var aliasErrors: [String: String] = [:]

    let capture = ShortcutCapture()
    let permissions: PermissionsMonitor
    private weak var host: SettingsHost?
    private let configURL: URL

    init(host: SettingsHost, permissions: PermissionsMonitor, configURL: URL = LodestarPaths.configFile) {
        self.host = host
        self.permissions = permissions
        self.configURL = configURL
        self.hotkey = host.currentHotkey
        capture.onSuspendChange = { [weak host] in host?.setHotkeysSuspended($0) }
        refresh()
    }

    /// Re-reads state that may have changed outside the window.
    func refresh() {
        if let host {
            hotkey = host.currentHotkey
            catalog = host.commandCatalog()
            clipboardCount = host.clipboardEntryCount()
        }
        launchAtLogin = LaunchAtLogin.state
        config = LodestarConfig.load(from: configURL)
    }

    // MARK: Derived values

    var preferences: CommandPreferences { config.commandPreferences }
    var clipboardHistoryEnabled: Bool { config.clipboardHistoryEnabled ?? true }
    var clipboardHistoryLimit: Int { config.clipboardHistoryLimit ?? 300 }
    var appearance: AppearanceMode { AppearanceMode(configValue: config.appearance) }
    var launcherPosition: LauncherPosition { LauncherPosition(configValue: config.launcherPosition) }
    var showMenuBarIcon: Bool { config.showMenuBarIcon ?? true }
    var windowGap: Int { WindowGap.clamp(config.windowGap) }
    var emojiSkinTone: EmojiSkinTone { EmojiSkinTone(configValue: config.emojiSkinTone) }
    var hotkeyError: String? { capture.errorMessage(for: SettingsModel.launcherTarget) }
    var hotkeyWarning: String? { HotkeyConflicts.systemConflict(for: hotkey) }
    var configPath: String { (configURL.path as NSString).abbreviatingWithTildeInPath }

    func title(forCommand id: String) -> String { catalog.first { $0.descriptor.id == id }?.descriptor.title ?? id }

    // MARK: Launcher shortcut

    func toggleLauncherRecording() {
        capture.toggle(SettingsModel.launcherTarget) { [weak self] result in
            switch result {
            case .record(let spec): self?.applyLauncherHotkey(spec)
            case .clear: self?.applyLauncherHotkey(.default)
            }
        }
    }

    func restoreDefaultHotkey() {
        capture.cancel()
        applyLauncherHotkey(.default)
    }

    private func applyLauncherHotkey(_ spec: HotkeySpec) {
        guard let host else { return }
        if let owner = preferences.commandID(forHotkey: spec) {
            capture.report("\(spec) is already used by “\(title(forCommand: owner))”.", for: SettingsModel.launcherTarget)
            return
        }
        do {
            try host.applyHotkey(spec)
            capture.report(nil, for: SettingsModel.launcherTarget)
        } catch {
            capture.report(error.localizedDescription, for: SettingsModel.launcherTarget)
        }
        hotkey = host.currentHotkey
        config = LodestarConfig.load(from: configURL)
    }

    // MARK: Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            try LaunchAtLogin.setEnabled(enabled)
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = LaunchAtLogin.state
    }

    var launchAtLoginIsOn: Bool { launchAtLogin == .enabled || launchAtLogin == .requiresApproval }

    // MARK: Simple config values (applied live)

    func setClipboardHistoryEnabled(_ enabled: Bool) { save { $0.clipboardHistoryEnabled = enabled ? nil : false } }
    func setClipboardHistoryLimit(_ limit: Int) { save { $0.clipboardHistoryLimit = limit == 300 ? nil : limit } }
    func setAppearance(_ mode: AppearanceMode) { save { $0.appearance = mode.configValue } }
    func setLauncherPosition(_ position: LauncherPosition) { save { $0.launcherPosition = position.configValue } }
    func setShowMenuBarIcon(_ show: Bool) { save { $0.showMenuBarIcon = show ? nil : false } }
    func setEmojiSkinTone(_ tone: EmojiSkinTone) { save { $0.emojiSkinTone = tone.configValue } }
    func setWindowGap(_ gap: Int) { save { $0.windowGap = gap == 0 ? nil : WindowGap.clamp(gap) } }

    func clearClipboardHistory() {
        host?.clearClipboardHistory()
        clipboardCount = host?.clipboardEntryCount() ?? 0
    }

    // MARK: Commands

    func isEnabled(_ id: String) -> Bool { preferences.isEnabled(id) }

    func setEnabled(_ enabled: Bool, for id: String) {
        var prefs = preferences
        prefs.setEnabled(enabled, for: id)
        save { $0.commandPreferences = prefs }
    }

    /// Enables or disables every command in `ids` (a whole section).
    func setEnabled(_ enabled: Bool, forAll ids: [String]) {
        var prefs = preferences
        for id in ids { prefs.setEnabled(enabled, for: id) }
        save { $0.commandPreferences = prefs }
    }

    func setAlias(_ text: String, for id: String) {
        var prefs = preferences
        do {
            try prefs.setAlias(text, for: id)
            aliasErrors[id] = nil
            save { $0.commandPreferences = prefs }
        } catch AliasError.inUse(let owner) {
            aliasErrors[id] = "Already used by “\(title(forCommand: owner))”."
        } catch {
            aliasErrors[id] = error.localizedDescription
        }
    }

    func toggleCommandRecording(_ id: String) {
        capture.toggle(id) { [weak self] result in
            switch result {
            case .record(let spec): self?.setCommandHotkey(spec, for: id)
            case .clear: self?.setCommandHotkey(nil, for: id)
            }
        }
    }

    func setCommandHotkey(_ spec: HotkeySpec?, for id: String) {
        guard let host else { return }
        var prefs = preferences
        let previous = prefs.hotkey(for: id)
        do {
            try prefs.setHotkey(spec, for: id, launcherHotkey: hotkey)
        } catch CommandHotkeyError.inUse(let owner) {
            capture.report("Already used by “\(title(forCommand: owner))”.", for: id); return
        } catch {
            capture.report(error.localizedDescription, for: id); return
        }
        do {
            try host.registerCommandHotkey(prefs.isEnabled(id) ? spec : nil, for: id)
        } catch {
            capture.report(error.localizedDescription, for: id); return
        }
        if save({ $0.commandPreferences = prefs }) {
            capture.report(nil, for: id)
        } else {
            try? host.registerCommandHotkey(previous, for: id)
        }
    }

    /// Clears every enable/alias/hotkey setting. The host re-syncs shortcuts.
    func resetCommandSettings() {
        aliasErrors = [:]
        save { $0.commandPreferences = CommandPreferences() }
    }

    func reloadExtensions() {
        host?.reloadExtensions()
        catalog = host?.commandCatalog() ?? []
    }

    // MARK: Navigation

    func showLauncher() { host?.showLauncher() }
    func showOnboarding() { host?.showOnboarding() }
    func openSettings(_ tab: SettingsTab? = nil) { host?.openSettings(tab: tab) }

    // MARK: Saving

    @discardableResult
    private func save(_ change: (inout LodestarConfig) -> Void) -> Bool {
        do {
            let saved = try LodestarConfig.update(at: configURL, change)
            config = saved
            configError = nil
            host?.configDidChange(saved)
            clipboardCount = host?.clipboardEntryCount() ?? 0
            return true
        } catch {
            configError = error.localizedDescription
            return false
        }
    }
}

/// Hosts `SettingsView` in a fixed-size window with a transparent title bar,
/// a vibrant background and a centered tab bar. Lodestar is an accessory
/// app, so showing it also activates the app.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 860, height: 580)
    let model: SettingsModel

    private(set) lazy var window: NSWindow = {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsWindowController.size),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Lodestar Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        let hosting = NSHostingView(rootView: SettingsView(model: model))
        // The window has a fixed size; don't let SwiftUI's ideal size resize it.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(SettingsWindowController.size)
        window.center()
        window.setFrameAutosaveName("LodestarSettings")
        return window
    }()

    init(model: SettingsModel) {
        self.model = model
    }

    func show(tab: SettingsTab? = nil) {
        model.refresh()
        if let tab { model.selectedTab = tab }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if !watching { watching = true; model.permissions.startWatching() }
    }

    private var watching = false

    func windowDidResignKey(_ notification: Notification) {
        model.capture.cancel()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        model.capture.cancel()
        if watching { watching = false; model.permissions.stopWatching() }
    }
}
