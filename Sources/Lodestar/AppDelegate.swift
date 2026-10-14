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

        if CommandLine.arguments.contains("--show") { showPanel() }
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
        hotKey = GlobalHotKey(spec: hotkeySpec) { [weak self] in self?.togglePanel() }
        if hotKey == nil {
            NSLog("Lodestar: could not register \(hotkeySpec) — it may be taken by another app (Spotlight uses ⌘Space).")
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
            guard let self, event.window === self.panel else { return event }
            let cmd = event.modifierFlags.contains(.command)
            switch event.keyCode {
            case 125: self.model.moveSelection(1); return nil                      // ↓
            case 126: self.model.moveSelection(-1); return nil                     // ↑
            case 36, 76: self.model.runSelected(actionIndex: cmd ? 1 : 0); return nil  // Return / Enter
            case 53: self.model.escape(); return nil                               // Esc
            case 40 where cmd: self.model.showActionPanel(); return nil            // ⌘K
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
