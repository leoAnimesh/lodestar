import AppKit
import LodestarCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: LauncherPanel!
    private var model: LauncherViewModel!
    private var root: RootScreen!
    private var hotKey: GlobalHotKey?
    private var statusItem: NSStatusItem?
    private var keyMonitor: Any?
    private var clipboard: ClipboardHistory?
    private var config = LodestarConfig()
    private var hotkeySpec = HotkeySpec.default
    private var openMenuItem: NSMenuItem?
    private var settings: SettingsWindowController?  // created on first open

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = LodestarConfig.load(from: LodestarPaths.configFile)
        ensureConfigDirectories()

        let frecency = FrecencyStore(url: LodestarPaths.supportDirectory.appendingPathComponent("frecency.json"))
        let apps = AppIndex(extraDirectories: config.appDirectories ?? [])
        if config.clipboardHistoryEnabled ?? true {
            let history = ClipboardHistory(limit: config.clipboardHistoryLimit ?? 300,
                                           storeURL: LodestarPaths.supportDirectory.appendingPathComponent("clipboard.json"))
            history.start()
            clipboard = history
        }
        let scripts = ScriptCommandStore(directory: LodestarPaths.scriptsDirectory)
        let extensions = ExtensionRegistry(directory: LodestarPaths.extensionsDirectory)
        scripts.reload()
        extensions.reload()

        root = RootScreen(apps: apps, clipboard: clipboard, scripts: scripts, extensions: extensions, frecency: frecency)
        root.onReload = {
            scripts.reload()
            extensions.reload()
        }
        model = LauncherViewModel(root: root, frecency: frecency)
        model.onHide = { [weak self] in self?.hidePanel() }

        panel = LauncherPanel(rootView: LauncherView(model: model))
        panel.delegate = self

        apps.refreshIfStale(maxAge: 0) { [weak self] in
            if self?.panel.isVisible == true { self?.model.refresh() }
        }

        installKeyMonitor()
        installStatusItem()
        registerHotKey()

        // An accessory app shows nothing at launch, which looks like "nothing opened".
        // Show the launcher the first time it runs (and with --show).
        let firstRun = !UserDefaults.standard.bool(forKey: "didShowFirstLaunch")
        if firstRun || CommandLine.arguments.contains("--show") {
            UserDefaults.standard.set(true, forKey: "didShowFirstLaunch")
            showPanel()
        }
        NSLog("Lodestar: running; press \(hotkeySpec) or use the menu bar icon to open the launcher")
    }

    /// Opening the app again (`open Lodestar.app`, Finder, Spotlight) while it is
    /// already running shows the launcher instead of silently doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    private func ensureConfigDirectories() {
        let fm = FileManager.default
        for dir in [LodestarPaths.scriptsDirectory, LodestarPaths.extensionsDirectory, LodestarPaths.supportDirectory] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: Hotkey

    private func registerHotKey() {
        if let raw = config.hotkey {
            if let spec = HotkeySpec(raw) { hotkeySpec = spec } else { NSLog("Lodestar: invalid hotkey '\(raw)', using default") }
        }
        let hotKey = GlobalHotKey { [weak self] in self?.togglePanel() }
        self.hotKey = hotKey
        do {
            try hotKey.register(hotkeySpec)
        } catch {
            NSLog("Lodestar: could not register \(hotkeySpec) — it may be taken by another app (Spotlight uses ⌘Space). \(error.localizedDescription)")
        }
    }

    // MARK: Panel

    @objc func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    func showPanel() {
        root.apps.refreshIfStale { [weak self] in
            if self?.panel.isVisible == true { self?.model.refresh() }
        }
        model.prepareForShow()
        panel.positionOnActiveScreen()
        panel.makeKeyAndOrderFront(nil)
    }

    func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        model.popToRoot()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking elsewhere dismisses the launcher, like a popover.
        // Defer so that modal alerts we present ourselves don't count.
        DispatchQueue.main.async { [weak self] in
            guard let self, NSApp.modalWindow == nil, !self.panel.isKeyWindow else { return }
            self.hidePanel()
        }
    }

    /// Arrow keys, Return, Escape and ⌘K are handled here rather than in the
    /// text field so they work regardless of SwiftUI focus details.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if let settings = self.settings, event.window === settings.window, !settings.model.isRecording,
               event.modifierFlags.contains(.command), event.keyCode == 13 {  // ⌘W (no main menu in an accessory app)
                settings.window.performClose(nil)
                return nil
            }
            guard event.window === self.panel else { return event }
            let cmd = event.modifierFlags.contains(.command)
            switch event.keyCode {
            case 125: self.model.moveSelection(1); return nil                      // ↓
            case 126: self.model.moveSelection(-1); return nil                     // ↑
            case 36, 76: self.model.runSelected(actionIndex: cmd ? 1 : 0); return nil  // Return / Enter
            case 53: self.model.escape(); return nil                               // Esc
            case 40 where cmd: self.model.showActionPanel(); return nil            // ⌘K
            case 43 where cmd: self.openSettings(); return nil                     // ⌘,
            case 45 where event.modifierFlags.contains(.control): self.model.moveSelection(1); return nil  // ⌃N
            case 35 where event.modifierFlags.contains(.control): self.model.moveSelection(-1); return nil // ⌃P
            default: return event
            }
        }
    }

    // MARK: Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: "Lodestar")
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Lodestar (\(hotkeySpec))", action: #selector(togglePanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        openMenuItem = open
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let reload = NSMenuItem(title: "Reload Scripts and Extensions", action: #selector(reloadExtensions), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)
        let config = NSMenuItem(title: "Open Config Folder", action: #selector(openConfig), keyEquivalent: "")
        config.target = self
        menu.addItem(config)
        let ax = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(requestAccessibility), keyEquivalent: "")
        ax.target = self
        menu.addItem(ax)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Lodestar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc func openSettings() {
        hidePanel()
        let settings = self.settings ?? SettingsWindowController(model: SettingsModel(host: self))
        self.settings = settings
        settings.show()
    }

    @objc private func reloadExtensions() {
        root.onReload?()
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(LodestarPaths.configDirectory)
    }

    @objc private func requestAccessibility() {
        if SystemActions.ensureAccessibility(prompt: true) {
            let alert = NSAlert()
            alert.messageText = "Accessibility access is already granted."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}

// MARK: Settings

extension AppDelegate: SettingsHost {
    var currentHotkey: HotkeySpec { hotKey?.spec ?? hotkeySpec }

    func applyHotkey(_ spec: HotkeySpec) throws {
        guard let hotKey else { return }
        let previous = hotKey.spec
        try hotKey.register(spec)
        do {
            // The default is stored as "no key", so the README's default applies.
            config = try LodestarConfig.update(at: LodestarPaths.configFile) {
                $0.hotkey = spec.isSameShortcut(as: .default) ? nil : spec.configString
            }
        } catch {
            // Keep the live hotkey and the file in agreement.
            if let previous { try? hotKey.register(previous) }
            throw error
        }
        hotkeySpec = spec
        openMenuItem?.title = "Open Lodestar (\(spec))"
    }

    func setHotkeySuspended(_ suspended: Bool) {
        suspended ? hotKey?.suspend() : hotKey?.resume()
    }
}
