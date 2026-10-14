import AppKit
import LodestarCore

/// Loads executable scripts with `@lodestar.*` metadata from
/// ~/.config/lodestar/scripts and turns them into launcher commands.
final class ScriptCommandStore {
    private(set) var commands: [ScriptCommand] = []
    let directory: URL

    init(directory: URL) { self.directory = directory }

    func reload() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            commands = []
            return
        }
        commands = files.compactMap { url -> ScriptCommand? in
            guard !url.lastPathComponent.hasPrefix("."),
                  let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            let head = String(decoding: handle.readData(ofLength: 8 * 1024), as: UTF8.self)
            return ScriptCommand.parse(contents: head, path: url.path)
        }
        .sorted { $0.title < $1.title }
    }

    /// Runs off the main thread and reports the outcome back on main.
    static func execute(_ command: ScriptCommand, argument: String?, host: ScreenHost?) {
        let url = URL(fileURLWithPath: command.path)
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var executable = command.path
            var args: [String] = argument.map { [$0] } ?? []
            if !fm.isExecutableFile(atPath: command.path) {
                // Fall back to the shebang interpreter via /usr/bin/env-less sh.
                executable = "/bin/sh"
                args = [command.path] + args
            }
            let result = SystemActions.run(executable, args, currentDirectory: url.deletingLastPathComponent())
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                if result.status != 0 {
                    host?.showDetail(title: "\(command.title) failed (exit \(result.status))", text: output)
                    return
                }
                switch command.mode {
                case .silent:
                    break
                case .compact:
                    let last = output.split(separator: "\n").last.map(String.init) ?? "Done"
                    host?.showToast(last)
                case .fullOutput:
                    host?.showDetail(title: command.title, text: output.isEmpty ? "(no output)" : output)
                }
            }
        }
    }

    static let template = """
    #!/bin/bash

    # Required parameters:
    # @lodestar.schemaVersion 1
    # @lodestar.title My Script
    # @lodestar.mode fullOutput

    # Optional parameters:
    # @lodestar.icon 🤖
    # @lodestar.description Describe what this script does
    # @lodestar.keywords example
    # @lodestar.argument1 { "type": "text", "placeholder": "Input" }

    echo "Hello from Lodestar! Argument: $1"

    """
}

/// Collects the single argument for a script command before running it.
final class ScriptArgumentScreen: ListScreen {
    let title: String
    let placeholder: String
    weak var host: ScreenHost?
    private let command: ScriptCommand

    init(command: ScriptCommand) {
        self.command = command
        self.title = command.title
        self.placeholder = command.argumentPlaceholder ?? "Argument"
    }

    func search(_ query: String) -> [LauncherItem] {
        let cmd = command
        return [LauncherItem(
            id: "script-arg",
            title: query.isEmpty ? "Run \(cmd.title)" : "Run \(cmd.title) with “\(query)”",
            subtitle: cmd.description,
            icon: ItemIcon.parse(cmd.icon, fallback: "terminal"),
            actions: [LauncherAction("Run Script", symbol: "play") { [weak self] in
                ScriptCommandStore.execute(cmd, argument: query, host: self?.host)
                return cmd.mode == .silent ? .close : .stay
            }],
            tracksUsage: false
        )]
    }
}
