import AppKit
import ApplicationServices

/// Small wrappers around macOS APIs shared by several providers.
enum SystemActions {
    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Copies `text`, then synthesizes ⌘V into the frontmost app.
    /// Posting keyboard events requires the Accessibility permission.
    static func paste(_ text: String) {
        copy(text)
        guard ensureAccessibility(prompt: true) else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Returns whether we're trusted for Accessibility, optionally showing
    /// the system prompt that links to System Settings.
    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    @discardableResult
    static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("Lodestar AppleScript error: \(error)") ; return nil }
        return result?.stringValue ?? ""
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Modal confirmation for destructive commands.
    static func confirm(_ message: String, info: String = "", button: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Runs a process synchronously with a timeout; returns combined output.
    static func run(_ executable: String, _ args: [String], currentDirectory: URL? = nil, timeout: TimeInterval = 30) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = currentDirectory
        process.environment = augmentedEnvironment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let handle = pipe.fileHandleForReading
        var data = Data()
        let lock = NSLock()
        handle.readabilityHandler = { h in
            let chunk = h.availableData
            lock.lock(); data.append(chunk); lock.unlock()
        }
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch {
            handle.readabilityHandler = nil
            return (-1, "Failed to launch: \(error.localizedDescription)")
        }
        var timedOut = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            finished.wait()
        }
        handle.readabilityHandler = nil
        let rest = handle.readDataToEndOfFile()
        lock.lock(); data.append(rest); lock.unlock()
        if timedOut { data.append(Data("\n[timed out]".utf8)) }
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// GUI apps launched from Finder get a minimal PATH; add the usual
    /// Homebrew / Node locations so scripts and extensions find `node`.
    static func augmentedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
                     NSHomeDirectory() + "/.volta/bin", NSHomeDirectory() + "/.local/bin"]
        let current = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        env["PATH"] = (current + extra.filter { !current.contains($0) }).joined(separator: ":")
        env["LODESTAR"] = "1"
        return env
    }
}
