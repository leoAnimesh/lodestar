import AppKit
import LodestarCore

/// The top-level search: applications, built-in commands, script commands,
/// extension commands, an inline calculator and web-search fallbacks.
final class RootScreen: ListScreen {
    let title = "Lodestar"
    let placeholder = "Search apps and commands…"
    weak var host: ScreenHost?

    let apps: AppIndex
    let clipboard: ClipboardHistory?
    let scripts: ScriptCommandStore
    let extensions: ExtensionRegistry
    let frecency: FrecencyStore
    var onReload: (() -> Void)?

    init(apps: AppIndex, clipboard: ClipboardHistory?, scripts: ScriptCommandStore, extensions: ExtensionRegistry, frecency: FrecencyStore) {
        self.apps = apps
        self.clipboard = clipboard
        self.scripts = scripts
        self.extensions = extensions
        self.frecency = frecency
    }

    // MARK: Search

    func search(_ query: String) -> [LauncherItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let all = allItems()

        if trimmed.isEmpty {
            // No query: show most-used items, then a few useful defaults.
            let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var result = frecency.mostUsed(limit: 8).compactMap { byID[$0] }
            for id in ["cmd:clipboard", "cmd:files", "wm:Left Half", "wm:Right Half", "wm:Maximize"] where !result.contains(where: { $0.id == id }) {
                if let item = byID[id] { result.append(item) }
            }
            return result
        }

        var results: [LauncherItem] = []
        if let value = Calculator.evaluateIfCalculation(trimmed) {
            results.append(calculatorItem(expression: trimmed, value: value))
        }

        let candidates = all.map { SearchCandidate(id: $0.id, title: $0.title, keywords: $0.keywords) }
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for ranked in Ranker.rank(candidates, query: trimmed, frecency: frecency, limit: 40) {
            guard var item = byID[ranked.candidate.id] else { continue }
            item.matchedIndices = ranked.matchedIndices
            results.append(item)
        }

        if let url = urlFromQuery(trimmed) {
            results.append(LauncherItem(id: "fallback:url", title: "Open \(url.absoluteString)", subtitle: nil,
                                        icon: .symbol("link"),
                                        actions: [LauncherAction("Open URL", symbol: "safari") { SystemActions.open(url); return .close }],
                                        tracksUsage: false))
        }
        results.append(webSearchItem(trimmed))
        return results
    }

    private func urlFromQuery(_ q: String) -> URL? {
        guard !q.contains(" "), q.contains(".") || q.hasPrefix("localhost") else { return nil }
        if q.hasPrefix("http://") || q.hasPrefix("https://") { return URL(string: q) }
        let host = q.split(separator: "/").first.map(String.init) ?? q
        guard let tld = host.split(separator: ".").last, tld.count >= 2, tld.allSatisfy(\.isLetter) || host.hasPrefix("localhost") else { return nil }
        return URL(string: "https://" + q)
    }

    private func webSearchItem(_ q: String) -> LauncherItem {
        var comps = URLComponents(string: "https://duckduckgo.com/")!
        comps.queryItems = [URLQueryItem(name: "q", value: q)]
        let url = comps.url!
        return LauncherItem(id: "fallback:web", title: "Search the web for “\(q)”", subtitle: nil, icon: .symbol("globe"),
                            actions: [LauncherAction("Search", symbol: "safari") { SystemActions.open(url); return .close }],
                            tracksUsage: false)
    }

    private func calculatorItem(expression: String, value: Double) -> LauncherItem {
        let formatted = Calculator.format(value)
        return LauncherItem(
            id: "calc", title: formatted, subtitle: "= \(expression)", icon: .symbol("equal.square"),
            accessory: "Calculator",
            actions: [
                LauncherAction("Copy Result", symbol: "doc.on.doc") { SystemActions.copy(formatted); return .close },
                LauncherAction("Paste Result", symbol: "doc.on.clipboard") { .closeThen { SystemActions.paste(formatted) } },
            ],
            tracksUsage: false
        )
    }

    // MARK: Item sources

    func allItems() -> [LauncherItem] {
        appItems() + builtinCommands() + windowCommands() + systemCommands() + scriptItems() + extensionItems()
    }

    private func appItems() -> [LauncherItem] {
        apps.apps.map { app in
            LauncherItem(
                id: "app:\(app.path)",
                title: app.name,
                subtitle: nil,
                icon: .file(app.path),
                accessory: "Application",
                keywords: [app.bundleID?.split(separator: ".").last.map(String.init)].compactMap { $0 },
                actions: [
                    LauncherAction("Open Application", symbol: "arrow.up.forward.app") {
                        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path),
                                                           configuration: NSWorkspace.OpenConfiguration())
                        return .close
                    },
                    LauncherAction("Reveal in Finder", symbol: "folder") { SystemActions.reveal(app.path); return .close },
                    LauncherAction("Copy Path", symbol: "doc.on.doc") { SystemActions.copy(app.path); return .toast("Path copied") },
                    LauncherAction("Quit Application", symbol: "xmark.circle") {
                        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID ?? "")
                        running.forEach { $0.terminate() }
                        return running.isEmpty ? .toast("\(app.name) is not running") : .close
                    },
                ]
            )
        }
    }

    private func command(_ id: String, _ title: String, subtitle: String? = nil, symbol: String,
                         keywords: [String] = [], accessory: String = "Command",
                         _ perform: @escaping () -> ActionOutcome) -> LauncherItem {
        LauncherItem(id: id, title: title, subtitle: subtitle, icon: .symbol(symbol), accessory: accessory,
                     keywords: keywords, actions: [LauncherAction("Run Command", symbol: "play", perform: perform)])
    }

    private func builtinCommands() -> [LauncherItem] {
        var items: [LauncherItem] = []
        if let clipboard {
            items.append(command("cmd:clipboard", "Clipboard History", symbol: "doc.on.clipboard", keywords: ["paste", "copy"]) {
                .push(ClipboardHistoryScreen(history: clipboard))
            })
        }
        items.append(command("cmd:files", "Search Files", symbol: "doc.text.magnifyingglass", keywords: ["find", "spotlight"]) {
            .push(FileSearchScreen())
        })
        items.append(command("cmd:reload", "Reload Scripts and Extensions", subtitle: "Lodestar", symbol: "arrow.clockwise") { [weak self] in
            self?.onReload?()
            let count = (self?.scripts.commands.count ?? 0) + (self?.extensions.extensions.count ?? 0)
            let errors = self?.extensions.loadErrors ?? []
            if !errors.isEmpty { return .detail(title: "Some extensions failed to load", text: errors.joined(separator: "\n\n")) }
            return .toast("Loaded \(count) scripts/extensions")
        })
        items.append(command("cmd:config", "Open Lodestar Config Folder", subtitle: "Lodestar", symbol: "folder.badge.gearshape",
                             keywords: ["settings", "preferences"]) {
            try? FileManager.default.createDirectory(at: LodestarPaths.configDirectory, withIntermediateDirectories: true)
            SystemActions.open(LodestarPaths.configDirectory)
            return .close
        })
        items.append(command("cmd:new-script", "Create Script Command", subtitle: "Lodestar", symbol: "doc.badge.plus") {
            let dir = LodestarPaths.scriptsDirectory
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var url = dir.appendingPathComponent("my-script.sh")
            var n = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = dir.appendingPathComponent("my-script-\(n).sh"); n += 1
            }
            try? ScriptCommandStore.template.write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            SystemActions.reveal(url.path)
            return .close
        })
        items.append(command("cmd:quit", "Quit Lodestar", subtitle: "Lodestar", symbol: "power") {
            NSApp.terminate(nil); return .close
        })
        return items
    }

    private func windowCommands() -> [LauncherItem] {
        WindowManager.Layout.allCases.map { layout in
            command("wm:\(layout.rawValue)", layout.rawValue, subtitle: "Window Management", symbol: layout.symbol,
                    keywords: ["window", "resize", "snap"], accessory: "Window") { [weak self] in
                .closeThen {
                    if case .failure(let error) = WindowManager.apply(layout) {
                        NSLog("Lodestar window management: \(error)")
                        if case .notTrusted = error { return }
                        self?.host?.showToast(error.description)
                    }
                }
            }
        }
    }

    private func systemCommands() -> [LauncherItem] {
        [
            command("sys:lock", "Lock Screen", subtitle: "System", symbol: "lock", accessory: "System") {
                .closeThen {
                    SystemActions.runAppleScript(#"tell application "System Events" to keystroke "q" using {control down, command down}"#)
                }
            },
            command("sys:sleep", "Sleep", subtitle: "System", symbol: "moon", accessory: "System") {
                .closeThen { SystemActions.runAppleScript(#"tell application "System Events" to sleep"#) }
            },
            command("sys:displaysleep", "Sleep Displays", subtitle: "System", symbol: "display", accessory: "System") {
                .closeThen { _ = SystemActions.run("/usr/bin/pmset", ["displaysleepnow"]) }
            },
            command("sys:restart", "Restart", subtitle: "System", symbol: "arrow.counterclockwise", accessory: "System") {
                guard SystemActions.confirm("Restart your Mac?", button: "Restart") else { return .stay }
                SystemActions.runAppleScript(#"tell application "System Events" to restart"#)
                return .close
            },
            command("sys:shutdown", "Shut Down", subtitle: "System", symbol: "power", accessory: "System") {
                guard SystemActions.confirm("Shut down your Mac?", button: "Shut Down") else { return .stay }
                SystemActions.runAppleScript(#"tell application "System Events" to shut down"#)
                return .close
            },
            command("sys:logout", "Log Out", subtitle: "System", symbol: "rectangle.portrait.and.arrow.right", accessory: "System") {
                guard SystemActions.confirm("Log out?", button: "Log Out") else { return .stay }
                SystemActions.runAppleScript(#"tell application "System Events" to log out"#)
                return .close
            },
            command("sys:trash", "Empty Trash", subtitle: "System", symbol: "trash", accessory: "System") {
                guard SystemActions.confirm("Empty the Trash?", info: "This cannot be undone.", button: "Empty Trash") else { return .stay }
                SystemActions.runAppleScript(#"tell application "Finder" to empty trash"#)
                return .toast("Trash emptied")
            },
            command("sys:dark", "Toggle Dark Mode", subtitle: "System", symbol: "circle.lefthalf.filled",
                    keywords: ["appearance", "light"], accessory: "System") {
                SystemActions.runAppleScript(#"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#)
                return .stay
            },
            command("sys:hideall", "Hide All Apps", subtitle: "System", symbol: "eye.slash", accessory: "System") {
                .closeThen {
                    for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.bundleIdentifier != "com.apple.finder" {
                        app.hide()
                    }
                }
            },
            command("sys:quitall", "Quit All Apps", subtitle: "System", symbol: "xmark.square", accessory: "System") {
                guard SystemActions.confirm("Quit all running apps?", info: "Apps may ask to save changes.", button: "Quit All") else { return .stay }
                let me = ProcessInfo.processInfo.processIdentifier
                for app in NSWorkspace.shared.runningApplications
                where app.activationPolicy == .regular && app.processIdentifier != me && app.bundleIdentifier != "com.apple.finder" {
                    app.terminate()
                }
                return .close
            },
            command("sys:eject", "Eject All Disks", subtitle: "System", symbol: "eject", accessory: "System") {
                SystemActions.runAppleScript(#"tell application "Finder" to eject (every disk whose ejectable is true)"#)
                return .toast("Ejecting disks")
            },
        ]
    }

    private func scriptItems() -> [LauncherItem] {
        scripts.commands.map { cmd in
            LauncherItem(
                id: "script:\(cmd.path)",
                title: cmd.title,
                subtitle: cmd.description ?? cmd.packageName,
                icon: ItemIcon.parse(cmd.icon, fallback: "terminal"),
                accessory: "Script",
                keywords: cmd.keywords,
                actions: [
                    LauncherAction("Run Script", symbol: "play") { [weak self] in
                        if cmd.needsArgument { return .push(ScriptArgumentScreen(command: cmd)) }
                        ScriptCommandStore.execute(cmd, argument: nil, host: self?.host)
                        return cmd.mode == .silent ? .close : .stay
                    },
                    LauncherAction("Reveal Script in Finder", symbol: "folder") { SystemActions.reveal(cmd.path); return .close },
                ]
            )
        }
    }

    private func extensionItems() -> [LauncherItem] {
        extensions.extensions.flatMap { installed in
            installed.manifest.commands.map { cmd in
                LauncherItem(
                    id: "ext:\(installed.manifest.name)/\(cmd.name)",
                    title: cmd.title,
                    subtitle: cmd.subtitle ?? installed.manifest.title,
                    icon: ItemIcon.parse(cmd.icon ?? installed.manifest.icon, fallback: "puzzlepiece.extension"),
                    accessory: "Extension",
                    keywords: cmd.keywords ?? [],
                    actions: [
                        LauncherAction("Run Command", symbol: "play") { [weak self] in
                            let session = ExtensionSession(installed: installed, command: cmd)
                            switch cmd.mode {
                            case .list:
                                return .push(session)
                            case .noView:
                                session.runDetached(host: self?.host)
                                return .stay
                            }
                        },
                        LauncherAction("Reveal Extension in Finder", symbol: "folder") {
                            SystemActions.reveal(installed.directory.path); return .close
                        },
                    ]
                )
            }
        }
    }
}
