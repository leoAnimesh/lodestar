import AppKit
import SwiftUI
import LodestarCore

/// What the settings screen needs from the app to change the live hotkey.
protocol SettingsHost: AnyObject {
    var currentHotkey: HotkeySpec { get }
    /// Registers `spec` and saves it. Throws, leaving the previous hotkey
    /// active and the config unchanged, if either step fails.
    func applyHotkey(_ spec: HotkeySpec) throws
    /// Releases the global hotkey while the recorder is capturing.
    func setHotkeySuspended(_ suspended: Bool)
}

final class SettingsModel: ObservableObject {
    @Published private(set) var hotkey: HotkeySpec
    @Published private(set) var isRecording = false
    /// Modifiers currently held while recording, e.g. "⌃⌥".
    @Published private(set) var recordingPreview = ""
    @Published var hotkeyError: String?

    @Published private(set) var launchAtLogin = LaunchAtLogin.State.disabled
    @Published var launchAtLoginError: String?

    @Published private(set) var clipboardHistoryEnabled = true
    @Published private(set) var clipboardHistoryLimit = 300
    @Published var configError: String?

    private weak var host: SettingsHost?
    private var monitor: Any?
    private let configURL: URL

    init(host: SettingsHost, configURL: URL = LodestarPaths.configFile) {
        self.host = host
        self.configURL = configURL
        self.hotkey = host.currentHotkey
        refresh()
    }

    /// Re-reads state that may have changed outside the window.
    func refresh() {
        if let host { hotkey = host.currentHotkey }
        launchAtLogin = LaunchAtLogin.state
        let config = LodestarConfig.load(from: configURL)
        clipboardHistoryEnabled = config.clipboardHistoryEnabled ?? true
        clipboardHistoryLimit = config.clipboardHistoryLimit ?? 300
    }

    // MARK: Hotkey recorder

    func toggleRecording() {
        isRecording ? cancelRecording() : startRecording()
    }

    func startRecording() {
        guard !isRecording else { return }
        hotkeyError = nil
        recordingPreview = ""
        isRecording = true
        host?.setHotkeySuspended(true)
        // A local monitor sees key events before key-equivalent handling, so
        // ⌘-combos are captured too. Everything is swallowed while recording.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            self.handle(event)
            return nil
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        stopRecording()
    }

    func restoreDefault() {
        cancelRecording()
        apply(.default)
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        recordingPreview = ""
        host?.setHotkeySuspended(false)
    }

    private func handle(_ event: NSEvent) {
        let flags = UInt(event.modifierFlags.rawValue)
        if event.type == .flagsChanged {
            recordingPreview = HotkeyRecorder.modifierPreview(cocoaFlags: flags)
            return
        }
        guard !event.isARepeat else { return }
        switch HotkeyRecorder.interpret(keyCode: UInt32(event.keyCode), cocoaFlags: flags) {
        case .cancel:
            stopRecording()
        case .restoreDefault:
            stopRecording()
            apply(.default)
        case .record(let spec):
            stopRecording()
            apply(spec)
        case .invalid(let error):
            hotkeyError = error.message
            NSSound.beep()
        }
    }

    private func apply(_ spec: HotkeySpec) {
        guard let host else { return }
        do {
            try host.applyHotkey(spec)
            hotkeyError = nil
        } catch {
            hotkeyError = error.localizedDescription
        }
        hotkey = host.currentHotkey
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

    // MARK: Clipboard history (read at launch)

    func setClipboardHistoryEnabled(_ enabled: Bool) {
        saveConfig { $0.clipboardHistoryEnabled = enabled }
    }

    func setClipboardHistoryLimit(_ limit: Int) {
        saveConfig { $0.clipboardHistoryLimit = limit }
    }

    private func saveConfig(_ change: (inout LodestarConfig) -> Void) {
        do {
            let saved = try LodestarConfig.update(at: configURL, change)
            clipboardHistoryEnabled = saved.clipboardHistoryEnabled ?? true
            clipboardHistoryLimit = saved.clipboardHistoryLimit ?? 300
            configError = nil
        } catch {
            configError = error.localizedDescription
        }
    }
}

/// Hosts `SettingsView` in an ordinary titled window. Lodestar is an accessory
/// app, so showing it also activates the app.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let model: SettingsModel
    private(set) lazy var window: NSWindow = {
        let controller = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: controller)
        window.title = "Lodestar Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }()

    init(model: SettingsModel) {
        self.model = model
    }

    func show() {
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        model.cancelRecording()
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelRecording()
    }
}
