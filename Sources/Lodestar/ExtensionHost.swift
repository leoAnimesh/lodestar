import AppKit
import LodestarCore

/// Discovers extensions in ~/.config/lodestar/extensions/<name>/manifest.json.
final class ExtensionRegistry {
    struct Installed {
        let manifest: ExtensionManifest
        let directory: URL
    }

    private(set) var extensions: [Installed] = []
    private(set) var loadErrors: [String] = []
    let directory: URL

    init(directory: URL) { self.directory = directory }

    func reload() {
        extensions = []
        loadErrors = []
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for dir in dirs where !dir.lastPathComponent.hasPrefix(".") {
            let manifestURL = dir.appendingPathComponent("manifest.json")
            guard fm.fileExists(atPath: manifestURL.path) else { continue }
            do {
                let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: Data(contentsOf: manifestURL))
                guard !manifest.run.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                extensions.append(Installed(manifest: manifest, directory: dir))
            } catch {
                loadErrors.append("\(dir.lastPathComponent): \(error)")
                NSLog("Lodestar: failed to load extension at \(dir.path): \(error)")
            }
        }
    }
}

/// One running command of an extension: a child process speaking
/// newline-delimited JSON over stdio (see LodestarCore/ExtensionProtocol.swift).
final class ExtensionSession: ListScreen {
    let title: String
    let placeholder: String
    weak var host: ScreenHost?

    private let installed: ExtensionRegistry.Installed
    private let command: ExtensionManifest.Command
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private var lineBuffer = LineBuffer()
    private var started = false
    private var lastItems: [LauncherItem] = []
    private var dynamicPlaceholder: String?

    /// For no-view commands the session lives detached from the UI until
    /// the process exits; keep a strong reference meanwhile.
    private static var detached: [ObjectIdentifier: ExtensionSession] = [:]

    init(installed: ExtensionRegistry.Installed, command: ExtensionManifest.Command) {
        self.installed = installed
        self.command = command
        self.title = "\(installed.manifest.title) — \(command.title)"
        self.placeholder = "Search \(command.title)…"
    }

    // MARK: Lifecycle

    func start(initialQuery: String = "") {
        guard !started else { return }
        started = true
        var argv = installed.manifest.run
        let first = argv.removeFirst()
        if first.hasPrefix("./") || first.hasPrefix("/") {
            let path = first.hasPrefix("/") ? first : installed.directory.appendingPathComponent(String(first.dropFirst(2))).path
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = argv
        } else {
            // Resolve interpreters like `node` or `python3` through PATH.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [first] + argv
        }
        process.currentDirectoryURL = installed.directory
        process.environment = SystemActions.augmentedEnvironment()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.receive(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [name = installed.manifest.name] handle in
            let data = handle.availableData
            if !data.isEmpty { NSLog("[ext \(name)] \(String(decoding: data, as: UTF8.self))") }
        }
        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { self?.processExited(status: proc.terminationStatus) }
        }
        do {
            try process.run()
            send(.run(command: command.name, query: initialQuery))
        } catch {
            host?.showDetail(title: "Could not start extension", text: "\(installed.manifest.run.joined(separator: " "))\n\n\(error.localizedDescription)")
        }
    }

    /// Runs a no-view command without pushing a screen.
    func runDetached(host: ScreenHost?) {
        self.host = host
        ExtensionSession.detached[ObjectIdentifier(self)] = self
        start()
    }

    private func processExited(status: Int32) {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        ExtensionSession.detached[ObjectIdentifier(self)] = nil
        if status != 0 && status != 15 /* SIGTERM from us */ {
            host?.showToast("\(installed.manifest.title) exited with status \(status)")
        }
    }

    func dismissed() {
        if process.isRunning { process.terminate() }
    }

    // MARK: ListScreen

    func search(_ query: String) -> [LauncherItem] {
        if !started {
            start(initialQuery: query)
            return []
        }
        send(.query(text: query))
        return lastItems  // keep showing old results until new ones arrive
    }

    // MARK: Protocol

    private func send(_ message: HostMessage) {
        guard process.isRunning else { return }
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: message.encodedLine())
        } catch {
            NSLog("Lodestar: write to extension failed: \(error)")
        }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        for line in lineBuffer.append(data) {
            do {
                handle(try JSONDecoder().decode(ExtensionMessage.self, from: line))
            } catch {
                NSLog("Lodestar: bad message from \(installed.manifest.name): \(String(decoding: line, as: UTF8.self)) — \(error)")
            }
        }
    }

    private func handle(_ message: ExtensionMessage) {
        switch message {
        case .items(let items, let placeholder):
            dynamicPlaceholder = placeholder
            lastItems = items.enumerated().map { convert($1, index: $0) }
            host?.setItems(lastItems, for: self)
        case .detail(let markdown):
            host?.showDetail(title: command.title, text: markdown)
        case .toast(let message):
            host?.showToast(message)
        case .close:
            host?.hideLauncher()
        case .error(let message):
            host?.showDetail(title: "\(installed.manifest.title) error", text: message)
        }
    }

    private func convert(_ item: ExtensionItem, index: Int) -> LauncherItem {
        let actions = (item.actions ?? []).map { action -> LauncherAction in
            switch action {
            case .open(let url):
                return LauncherAction("Open", symbol: "arrow.up.forward.app") {
                    if let u = URL(string: url) { SystemActions.open(u) }
                    return .close
                }
            case .copy(let text):
                return LauncherAction("Copy", symbol: "doc.on.doc") { SystemActions.copy(text); return .toast("Copied") }
            case .paste(let text):
                return LauncherAction("Paste", symbol: "doc.on.clipboard") { .closeThen { SystemActions.paste(text) } }
            case .callback(let id):
                return LauncherAction(id.capitalized, symbol: "bolt") { [weak self] in
                    self?.send(.callback(id: id))
                    return .stay
                }
            }
        }
        return LauncherItem(
            id: "ext:\(installed.manifest.name):\(item.id ?? String(index))",
            title: item.title,
            subtitle: item.subtitle,
            icon: ItemIcon.parse(item.icon, fallback: "puzzlepiece.extension"),
            accessory: item.accessory,
            actions: actions,
            tracksUsage: false
        )
    }
}
