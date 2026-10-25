import AppKit
import LodestarCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: LauncherPanel!
    private var model: LauncherViewModel!
    private var root: RootScreen!
    private var frecency: FrecencyStore!
    private var hotKey: GlobalHotKey?
    /// Global shortcuts bound to individual commands, keyed by command ID.
    private var commandHotKeys: [String: GlobalHotKey] = [:]
    private var statusItem: NSStatusItem?
    private var keyMonitor: Any?
    /// Loaded even when recording is off, so Settings can count and clear it.
    private var clipboard: ClipboardHistory!
    private var emoji: EmojiLibrary!
    private var config = LodestarConfig()
    private var hotkeySpec = HotkeySpec.default
    private var launcherPosition = LauncherPosition.upperThird
    private var openMenuItem: NSMenuItem?
    /// Keeps the Mac awake on request; drives the menu-bar cup indicator.
    let caffeinator = Caffeinator()
    private var stopCaffeinateItem: NSMenuItem?
    private let permissions = PermissionsMonitor()
    private lazy var settingsModel = SettingsModel(host: self, permissions: permissions)
    private var settings: SettingsWindowController?      // created on first open
    private var onboarding: OnboardingWindowController?  // created on first open

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = LodestarConfig.load(from: LodestarPaths.configFile)
        ensureConfigDirectories()

        frecency = FrecencyStore(url: LodestarPaths.supportDirectory.appendingPathComponent("frecency.json"))
        let apps = AppIndex(extraDirectories: config.appDirectories ?? [])
        clipboard = ClipboardHistory(limit: config.clipboardHistoryLimit ?? 300,
                                     storeURL: LodestarPaths.supportDirectory.appendingPathComponent("clipboard.json"))
        let scripts = ScriptCommandStore(directory: LodestarPaths.scriptsDirectory)
        let extensions = ExtensionRegistry(directory: LodestarPaths.extensionsDirectory)
        scripts.reload()
        extensions.reload()

        emoji = EmojiLibrary(usageURL: LodestarPaths.supportDirectory.appendingPathComponent("emoji.json"))
        emoji.preload()
        emoji.onChangeSkinTone = { [weak self] tone in self?.saveEmojiSkinTone(tone) }

        root = RootScreen(apps: apps, clipboard: nil, scripts: scripts, extensions: extensions, frecency: frecency)
        root.emoji = emoji
        root.onReload = {
            scripts.reload()
            extensions.reload()
        }
        root.onOpenSettings = { [weak self] in self?.openSettings(tab: nil) }
        root.onShowWelcome = { [weak self] in self?.showOnboarding() }
        root.colorPicker = ColorPicker(storeURL: LodestarPaths.supportDirectory.appendingPathComponent("colors.json"))
        root.caffeinator = caffeinator
        caffeinator.onChange = { [weak self] in
            guard let self else { return }
            self.updateCaffeinateIndicator()
            if self.panel?.isVisible == true { self.model.refresh() }
        }
        model = LauncherViewModel(root: root, frecency: frecency)
        model.onHide = { [weak self] in self?.hidePanel() }

        panel = LauncherPanel(rootView: LauncherView(model: model))
        panel.delegate = self

        apps.refreshIfStale(maxAge: 0) { [weak self] in
            if self?.panel.isVisible == true { self?.model.refresh() }
        }

        installKeyMonitor()
        registerHotKey()
        applyConfig(config)

        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), args.indices.contains(i + 1) {
            SnapshotTour(app: self, output: URL(fileURLWithPath: args[i + 1])).start()
            return
        }

        // First run shows the welcome window (it replaces the old "show the
        // launcher on first launch"); --show still opens the launcher.
        let defaults = UserDefaults.standard
        let decision = Onboarding.launchDecision(
            completedVersion: defaults.object(forKey: Onboarding.completedVersionKey) as? Int,
            legacyDidShowFirstLaunch: defaults.bool(forKey: Onboarding.legacyFirstLaunchKey),
            forceShow: args.contains("--onboarding"))
        if let v = decision.storeCompletedVersion { defaults.set(v, forKey: Onboarding.completedVersionKey) }
        if decision.removeLegacyKey { defaults.removeObject(forKey: Onboarding.legacyFirstLaunchKey) }
        if decision.showOnboarding {
            showOnboarding()
        } else if args.contains("--show") {
            showPanel()
        }
        NSLog("Lodestar: running; press \(hotkeySpec) or use the menu bar icon to open the launcher")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // macOS would drop the assertion with the process anyway; be explicit.
        caffeinator.stop()
    }

    /// Opening the app again (`open Lodestar.app`, Finder, Spotlight) while it is
    /// already running shows the launcher (or the welcome window, if it's open).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let onboarding, onboarding.window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            onboarding.window.makeKeyAndOrderFront(nil)
        } else {
            showPanel()
        }
        return false
    }

    private func ensureConfigDirectories() {
        let fm = FileManager.default
        for dir in [LodestarPaths.scriptsDirectory, LodestarPaths.extensionsDirectory, LodestarPaths.supportDirectory] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: Config

    /// Applies everything in config.json that can change while running.
    private func applyConfig(_ newConfig: LodestarConfig) {
        config = newConfig
        NSApp.appearance = {
            switch AppearanceMode(configValue: newConfig.appearance) {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }()
        launcherPosition = LauncherPosition(configValue: newConfig.launcherPosition)

        let recordClipboard = newConfig.clipboardHistoryEnabled ?? true
        clipboard.limit = max(newConfig.clipboardHistoryLimit ?? 300, 1)
        if recordClipboard {
            if root.clipboard == nil { clipboard.start() }
            root.clipboard = clipboard
        } else {
            clipboard.stop()
            root.clipboard = nil
        }

        if newConfig.showMenuBarIcon ?? true {
            if statusItem == nil { installStatusItem() }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }

        emoji.skinTone = EmojiSkinTone(configValue: newConfig.emojiSkinTone)
        root.preferences = newConfig.commandPreferences
        syncCommandHotKeys()
        if panel.isVisible { model.refresh() }
    }

    /// The launcher's "Change Default Skin Tone…" action.
    private func saveEmojiSkinTone(_ tone: EmojiSkinTone) {
        do {
            config = try LodestarConfig.update(at: LodestarPaths.configFile) { $0.emojiSkinTone = tone.configValue }
            settings?.model.refresh()
        } catch {
            model.showToast(error.localizedDescription)
        }
    }

    // MARK: Hotkeys

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

    /// Makes the registered command shortcuts match `root.preferences`.
    private func syncCommandHotKeys() {
        let bindings = root.preferences.hotkeyBindings
        let wanted = Set(bindings.map(\.id))
        for id in commandHotKeys.keys where !wanted.contains(id) { commandHotKeys[id] = nil }
        for (id, spec) in bindings {
            if commandHotKeys[id]?.spec?.isSameShortcut(as: spec) == true { continue }
            do {
                try commandHotKey(for: id).register(spec)
            } catch {
                NSLog("Lodestar: could not register \(spec) for \(id): \(error.localizedDescription)")
            }
        }
    }

    private func commandHotKey(for id: String) -> GlobalHotKey {
        if let existing = commandHotKeys[id] { return existing }
        let hk = GlobalHotKey { [weak self] in self?.runCommand(id) }
        if hotKey?.isSuspended == true { hk.suspend() }
        commandHotKeys[id] = hk
        return hk
    }

    /// Runs a command from its own shortcut. Commands that just do something
    /// (system commands) run without showing the launcher;
    /// commands with UI (clipboard history, extensions) open it.
    func runCommand(_ id: String) {
        guard let item = root.allItems().first(where: { $0.id == id }), let action = item.actions.first else { return }
        if item.tracksUsage { frecency.recordUse(of: id) }
        switch action.perform() {
        case .close:
            hidePanel()
        case .closeThen(let work):
            if panel.isVisible {
                hidePanel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
            } else {
                work()
            }
        case .stay:
            break
        case .push(let screen):
            showPanel()
            model.push(screen)
        case .detail(let title, let text):
            showPanel()
            model.showDetail(title: title, text: text)
        case .toast(let message):
            showPanel()
            model.showToast(message)
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
        panel.position(launcherPosition)
        panel.makeKeyAndOrderFront(nil)
    }

    func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        model.popToRoot()
    }

    /// For the snapshot tour: show the launcher with a query typed in.
    func showPanel(query: String) {
        showPanel()
        model.query = query
    }

    /// For the snapshot tour: show the launcher with a sub-screen pushed.
    func showPanel(pushing screen: ListScreen) {
        showPanel()
        model.push(screen)
    }

    var launcherWindow: NSWindow { panel }
    var statusItemWindow: NSWindow? { statusItem?.button?.window }

    /// For the snapshot tour: open a command's screen, type a query, and
    /// optionally select an item and open its ⌘K actions.
    func showCommand(_ id: String, query: String = "", select glyphIndex: Int? = nil, actions: Bool = false) {
        showPanel()
        // Run the command's action directly: runCommand would record usage,
        // and the tour must not change the user's frecency ranking.
        if let item = root.allItems().first(where: { $0.id == id }), let action = item.actions.first,
           case .push(let screen) = action.perform() {
            model.push(screen)
        }
        model.query = query
        if let glyphIndex { model.selectedIndex = min(glyphIndex, max(model.items.count - 1, 0)) }
        if actions { model.showActionPanel() }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        // Clicking elsewhere dismisses the launcher, like a popover.
        // Defer so that modal alerts we present ourselves don't count.
        DispatchQueue.main.async { [weak self] in
            guard let self, NSApp.modalWindow == nil, !self.panel.isKeyWindow, !SnapshotTour.isRunning else { return }
            self.hidePanel()
        }
    }

    /// Arrow keys, Return, Escape and ⌘K are handled here rather than in the
    /// text field so they work regardless of SwiftUI focus details.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let cmd = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            // ⌘W and ⌘1…⌘5 in our ordinary windows (an accessory app has no main menu).
            if cmd, !self.settingsModel.capture.isRecording {
                if event.keyCode == 13, let window = event.window,
                   window === self.settings?.window || window === self.onboarding?.window {
                    window.performClose(nil)
                    return nil
                }
                if let settings = self.settings, event.window === settings.window,
                   let digit = Int(event.charactersIgnoringModifiers ?? ""), (1...SettingsTab.allCases.count).contains(digit) {
                    settings.model.selectedTab = SettingsTab.allCases[digit - 1]
                    return nil
                }
            }
            guard event.window === self.panel else { return event }
            let command = event.modifierFlags.contains(.command)
            switch event.keyCode {
            case 123 where self.model.moveInGrid(.left): return nil                    // ← (grid screens)
            case 124 where self.model.moveInGrid(.right): return nil                   // →
            case 125: if !self.model.moveInGrid(.down) { self.model.moveSelection(1) }; return nil   // ↓
            case 126: if !self.model.moveInGrid(.up) { self.model.moveSelection(-1) }; return nil    // ↑
            case 51 where !command && self.model.backspaceOnEmptyQuery(): return nil  // ⌫ on empty query: back
            case 36, 76: self.model.runSelected(actionIndex: command ? 1 : 0); return nil  // Return / Enter
            case 53: self.model.escape(); return nil                                   // Esc
            case 40 where command: self.model.showActionPanel(); return nil            // ⌘K
            case 43 where command: self.openSettings(tab: nil); return nil             // ⌘,
            case 45 where event.modifierFlags.contains(.control): self.model.moveSelection(1); return nil  // ⌃N
            case 35 where event.modifierFlags.contains(.control): self.model.moveSelection(-1); return nil // ⌃P
            default: return event
            }
        }
    }

    // MARK: Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = .lodestarMenuBarStar()
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Lodestar (\(hotkeySpec))", action: #selector(togglePanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        openMenuItem = open
        let stopCaffeinate = NSMenuItem(title: "Stop Caffeinate", action: #selector(stopCaffeinateFromMenu), keyEquivalent: "")
        stopCaffeinate.target = self
        stopCaffeinate.image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)
        menu.addItem(stopCaffeinate)
        stopCaffeinateItem = stopCaffeinate
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let welcome = NSMenuItem(title: "Show Welcome…", action: #selector(showOnboardingFromMenu), keyEquivalent: "")
        welcome.target = self
        menu.addItem(welcome)
        menu.addItem(.separator())
        let reload = NSMenuItem(title: "Reload Scripts and Extensions", action: #selector(reloadFromMenu), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)
        let configItem = NSMenuItem(title: "Open Config Folder", action: #selector(openConfig), keyEquivalent: "")
        configItem.target = self
        menu.addItem(configItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Lodestar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        updateCaffeinateIndicator()
    }

    /// While Caffeinate is on, the menu-bar icon becomes a filled cup and the
    /// menu offers "Stop Caffeinate (42m left)".
    private func updateCaffeinateIndicator() {
        let active = caffeinator.isActive
        statusItem?.button?.image = active
            ? NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Lodestar — Caffeinate is on")
            : .lodestarMenuBarStar()
        statusItem?.button?.toolTip = active ? "Caffeinate: \(caffeinator.statusText ?? "on")" : nil
        stopCaffeinateItem?.isHidden = !active
        if active, let status = caffeinator.statusText {
            let detail = status.replacingOccurrences(of: "Active — ", with: "")
            stopCaffeinateItem?.title = "Stop Caffeinate (\(detail))"
        }
    }

    @objc private func stopCaffeinateFromMenu() {
        caffeinator.stop()
        HUD.show("Decaffeinated — your Mac can sleep", symbol: "moon.zzz")
    }

    @objc private func openSettingsFromMenu() { openSettings(tab: nil) }
    @objc private func showOnboardingFromMenu() { showOnboarding() }
    @objc private func reloadFromMenu() { reloadExtensions() }

    @objc private func openConfig() {
        NSWorkspace.shared.open(LodestarPaths.configDirectory)
    }

    // MARK: Windows

    var settingsWindowController: SettingsWindowController {
        if let settings { return settings }
        let created = SettingsWindowController(model: settingsModel)
        settings = created
        return created
    }

    var onboardingWindowController: OnboardingWindowController {
        if let onboarding { return onboarding }
        let created = OnboardingWindowController(model: settingsModel)
        created.onFinish = { [weak self] openLauncher in
            if openLauncher { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.showPanel() } }
        }
        onboarding = created
        return created
    }
}

// MARK: Settings host

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

    func setHotkeysSuspended(_ suspended: Bool) {
        for hk in [hotKey].compactMap({ $0 }) + Array(commandHotKeys.values) {
            suspended ? hk.suspend() : hk.resume()
        }
    }

    func registerCommandHotkey(_ spec: HotkeySpec?, for id: String) throws {
        guard let spec else { commandHotKeys[id] = nil; return }
        let isNew = commandHotKeys[id] == nil
        do {
            try commandHotKey(for: id).register(spec)
        } catch {
            if isNew { commandHotKeys[id] = nil }
            throw error
        }
    }

    func configDidChange(_ config: LodestarConfig) {
        applyConfig(config)
    }

    func commandCatalog() -> [RootScreen.CatalogEntry] { root.catalog() }

    func reloadExtensions() {
        root.onReload?()
        if panel.isVisible { model.refresh() }
    }

    func clipboardEntryCount() -> Int { clipboard.entries.count }
    func clearClipboardHistory() { clipboard.clear() }

    func showLauncher() { showPanel() }

    func showOnboarding() {
        hidePanel()
        onboardingWindowController.show()
    }

    func openSettings(tab: SettingsTab?) {
        hidePanel()
        settingsWindowController.show(tab: tab)
    }
}
