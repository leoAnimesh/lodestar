import AppKit
import LodestarCore

/// Records one keyboard shortcut at a time for any target (the launcher
/// shortcut or a command's shortcut). While recording, every global hotkey is
/// suspended so pressing an existing combo is captured instead of firing.
final class ShortcutCapture: ObservableObject {
    enum Result {
        case record(HotkeySpec)
        /// Delete/Backspace with no modifiers: restore the default (launcher) or clear (command).
        case clear
    }

    /// The target being recorded, e.g. "launcher" or a command ID.
    @Published private(set) var target: String?
    /// Modifiers held so far, e.g. "⌃⌥".
    @Published private(set) var preview = ""
    @Published var error: (target: String, message: String)?

    var onSuspendChange: ((Bool) -> Void)?
    private var monitor: Any?
    private var completion: ((Result) -> Void)?

    var isRecording: Bool { target != nil }
    func isRecording(_ t: String) -> Bool { target == t }
    func errorMessage(for t: String) -> String? { error?.target == t ? error?.message : nil }

    func toggle(_ t: String, completion: @escaping (Result) -> Void) {
        if target == t { cancel() } else { start(t, completion: completion) }
    }

    func start(_ t: String, completion: @escaping (Result) -> Void) {
        cancel()
        error = nil
        preview = ""
        target = t
        self.completion = completion
        onSuspendChange?(true)
        // A local monitor sees key events before key-equivalent handling, so
        // ⌘-combos are captured too. Everything is swallowed while recording.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.target != nil else { return event }
            self.handle(event)
            return nil
        }
    }

    func cancel() {
        guard target != nil else { return }
        finish()
    }

    func report(_ message: String?, for t: String) {
        error = message.map { (t, $0) }
    }

    private func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        target = nil
        preview = ""
        completion = nil
        onSuspendChange?(false)
    }

    private func handle(_ event: NSEvent) {
        let flags = UInt(event.modifierFlags.rawValue)
        if event.type == .flagsChanged {
            preview = HotkeyRecorder.modifierPreview(cocoaFlags: flags)
            return
        }
        guard !event.isARepeat, let t = target else { return }
        let done = completion
        switch HotkeyRecorder.interpret(keyCode: UInt32(event.keyCode), cocoaFlags: flags) {
        case .cancel:
            finish()
        case .restoreDefault:
            finish()
            done?(.clear)
        case .record(let spec):
            finish()
            done?(.record(spec))
        case .invalid(let err):
            error = (t, err.message)
            NSSound.beep()
        }
    }
}
