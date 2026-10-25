import AppKit
import LodestarCore

/// The top-level search: applications, built-in commands, script commands,
/// extension commands, an inline calculator and web-search fallbacks.
final class RootScreen: ListScreen {
    let title = "Lodestar"
    let placeholder = "Search apps and commands…"
    weak var host: ScreenHost?

    let apps: AppIndex
    var clipboard: ClipboardHistory?
    /// Emoji data for the "Search Emoji & Symbols" command and inline results.
    var emoji: EmojiLibrary?
    let scripts: ScriptCommandStore
    let extensions: ExtensionRegistry
    let frecency: FrecencyStore
    var onReload: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onShowWelcome: (() -> Void)?
    /// Pick Color / Color History (nil hides them).
    var colorPicker: ColorPicker?
    /// Caffeinate / Decaffeinate (nil hides them).
    var caffeinator: Caffeinator?
    /// Enable/alias/hotkey settings; disabled commands never appear in search.
    var preferences = CommandPreferences()

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
        let caffeinated = caffeinator?.isActive ?? false
        let all = CaffeinateCommands.arrange(allItems(), active: caffeinated)

        if trimmed.isEmpty {
            // No query: show most-used items, then a few useful defaults.
            let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var result = frecency.mostUsed(limit: 8).compactMap { byID[$0] }
            // While caffeinated, the way out leads the list.
            if caffeinated, let decaf = byID[CaffeinateCommands.decaffeinateID] {
                result.removeAll { $0.id == decaf.id }
                result.insert(decaf, at: 0)
            }
            for id in ["cmd:clipboard", "cmd:emoji", "cmd:files", ColorPickerCommands.pickID, ColorPickerCommands.historyID, CaffeinateDuration.indefinitely.commandID] where !result.contains(where: { $0.id == id }) {
                if let item = byID[id] { result.append(item) }
            }
            return result.map(RootScreen.withTile)
        }

        var results: [LauncherItem] = []
        if let value = Calculator.evaluateIfCalculation(trimmed) {
            results.append(calculatorItem(expression: trimmed, value: value))
        }

        let candidates = all.map { SearchCandidate(id: $0.id, title: $0.title, keywords: $0.keywords) }
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var ranked: [String: [Int]] = [:]
        var order: [String] = []
        for r in Ranker.rank(candidates, query: trimmed, frecency: frecency, limit: 40) {
            ranked[r.candidate.id] = r.matchedIndices
            order.append(r.candidate.id)
        }
        // An exact alias match goes first, even if fuzzy ranking missed it.
        order = preferences.promotingAlias(of: trimmed, in: order, available: Set(byID.keys))
        order = CaffeinateState.arrange(order, active: caffeinated, decaffeinateID: CaffeinateCommands.decaffeinateID)
        for id in order {
            guard var item = byID[id] else { continue }
            item.matchedIndices = ranked[id] ?? []
            if ranked[id] == nil, let alias = preferences.alias(for: id) { item.accessory = "Alias “\(alias)”" }
            results.append(item)
        }

        // A few emoji whose name is exactly the query ("rocket"), after apps
        // and commands but before the URL / web fallbacks.
        results += inlineEmoji(trimmed)

        if let url = urlFromQuery(trimmed) {
            results.append(LauncherItem(id: "fallback:url", title: "Open \(url.absoluteString)", subtitle: nil,
                                        icon: .symbol("link"),
                                        actions: [LauncherAction("Open URL", symbol: "safari") { SystemActions.open(url); return .close }],
                                        tracksUsage: false))
        }
        results.append(webSearchItem(trimmed))
        return results.map(RootScreen.withTile)
    }

    /// Gives built-in command icons their colored tile (IconTint).
    static func withTile(_ item: LauncherItem) -> LauncherItem {
        var copy = item
        copy.icon = item.icon.tinted(for: item.id)
        return copy
    }

    private func inlineEmoji(_ query: String) -> [LauncherItem] {
        guard let emoji, preferences.isEnabled("cmd:emoji"), let catalog = emoji.catalog else { return [] }
        return EmojiSearch.strongMatches(query, in: catalog, limit: 3).map { item in
            var row = emoji.launcherItem(item, idPrefix: "emoji", section: nil) { [weak self] in
                guard let self else { return }
                self.host?.setItems(self.search(query), for: self)
            }
            row.subtitle = "Emoji"
            row.accessory = catalog.category(of: item)?.name
            return row
        }
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
            id: "calc", title: formatted, subtitle: "= \(expression)", icon: .symbol("equal"),
            accessory: "Calculator",
            actions: [
                LauncherAction("Copy Result", symbol: "doc.on.doc") { SystemActions.copy(formatted); return .close },
                LauncherAction("Paste Result", symbol: "doc.on.clipboard") { .closeThen { SystemActions.paste(formatted) } },
            ],
            tracksUsage: false
        )
    }

    // MARK: Item sources

    /// Everything searchable: apps plus enabled commands, with aliases added as keywords.
    func allItems() -> [LauncherItem] {
        let commands = preferences.enabledOnly(commandItems(), id: \.id).map { item -> LauncherItem in
            guard let alias = preferences.alias(for: item.id) else { return item }
            var copy = item
            copy.keywords.append(alias)
            return copy
        }
        return appItems() + commands
    }

    /// Every command, enabled or not (apps excluded).
    func commandItems() -> [LauncherItem] {
        builtinCommands() + utilityCommands() + systemCommands() + scriptItems() + extensionItems()
    }

    /// Color picker and caffeinate commands (see Providers/ColorPicker.swift, CaffeinateCommands.swift).
    private func utilityCommands() -> [LauncherItem] {
        (colorPicker.map(ColorPickerCommands.items) ?? []) + (caffeinator.map(CaffeinateCommands.items) ?? [])
    }

    /// One row per command for Settings › Extensions.
    struct CatalogEntry {
        let descriptor: CommandDescriptor
        let icon: ItemIcon
        /// A file or folder to reveal (script file, extension folder).
        let location: URL?
        let summary: String
    }

    func catalog() -> [CatalogEntry] {
        var entries: [CatalogEntry] = []
        for item in builtinCommands() {
            entries.append(CatalogEntry(
                descriptor: CommandDescriptor(id: item.id, title: item.title, subtitle: item.subtitle, kind: .command, group: "Lodestar", keywords: item.keywords),
                icon: item.icon.tinted(for: item.id), location: nil, summary: RootScreen.builtinSummaries[item.id] ?? "A built-in Lodestar command."))
        }
        for item in utilityCommands() {
            entries.append(CatalogEntry(
                descriptor: CommandDescriptor(id: item.id, title: item.title, subtitle: "Utilities", kind: .command, group: "Utilities", keywords: item.keywords),
                icon: item.icon.tinted(for: item.id), location: nil,
                summary: ColorPickerCommands.summaries[item.id] ?? CaffeinateCommands.summaries[item.id] ?? "A built-in Lodestar command."))
        }
        for item in systemCommands() {
            entries.append(CatalogEntry(
                descriptor: CommandDescriptor(id: item.id, title: item.title, subtitle: "System", kind: .system, group: "System", keywords: item.keywords),
                icon: item.icon.tinted(for: item.id), location: nil,
                summary: "A system command. Some of these ask for Automation access the first time they run."))
        }
        for cmd in scripts.commands {
            entries.append(CatalogEntry(
                descriptor: CommandDescriptor(id: "script:\(cmd.path)", title: cmd.title, subtitle: cmd.description ?? cmd.packageName,
                                              kind: .script, group: "Script Commands", keywords: cmd.keywords),
                icon: ItemIcon.parse(cmd.icon, fallback: "terminal").tinted(for: "script:\(cmd.path)"), location: URL(fileURLWithPath: cmd.path),
                summary: cmd.description ?? "Runs \((cmd.path as NSString).lastPathComponent) (\(cmd.mode.rawValue) output)."))
        }
        for installed in extensions.extensions {
            for cmd in installed.manifest.commands {
                entries.append(CatalogEntry(
                    descriptor: CommandDescriptor(id: "ext:\(installed.manifest.name)/\(cmd.name)", title: cmd.title,
                                                  subtitle: cmd.subtitle ?? installed.manifest.title, kind: .extension,
                                                  group: installed.manifest.title, keywords: cmd.keywords ?? []),
                    icon: ItemIcon.parse(cmd.icon ?? installed.manifest.icon, fallback: "puzzlepiece.extension")
                        .tinted(for: "ext:\(installed.manifest.name)/\(cmd.name)"),
                    location: installed.directory,
                    summary: installed.manifest.description ?? "An extension command (\(cmd.mode.rawValue))."))
            }
        }
        return entries
    }

    static let builtinSummaries: [String: String] = [
        "cmd:clipboard": "Browse and search text you've copied. Return pastes into the frontmost app.",
        "cmd:files": "Finds files in your home folder with Spotlight as you type.",
        "cmd:emoji": "Browse and search every Unicode emoji plus arrows, math, currency, keyboard and other symbols. Return pastes into the frontmost app, ⌘K copies the name or code point and manages favorites. Strong matches (such as “rocket”) also appear in the main search.",
        "cmd:reload": "Re-reads the scripts and extensions folders.",
        "cmd:config": "Opens ~/.config/lodestar in Finder.",
        "cmd:new-script": "Creates a script command from a template and reveals it in Finder.",
        "cmd:settings": "Opens this window.",
        "cmd:welcome": "Opens the welcome tour again.",
        "cmd:quit": "Quits Lodestar.",
    ]

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
        if let emoji {
            items.append(command("cmd:emoji", "Search Emoji & Symbols", symbol: "face.smiling",
                                 keywords: ["emoji", "symbols", "smiley", "unicode", "character", "glyph", "arrows", "keyboard symbols"]) {
                .push(EmojiScreen(library: emoji))
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
        items.append(command("cmd:settings", "Lodestar Settings", subtitle: "Lodestar", symbol: "gearshape",
                             keywords: ["preferences", "settings", "extensions"]) { [weak self] in
            .closeThen { self?.onOpenSettings?() }
        })
        items.append(command("cmd:welcome", "Show Welcome Screen", subtitle: "Lodestar", symbol: "sparkles",
                             keywords: ["onboarding", "tour", "help", "permissions"]) { [weak self] in
            .closeThen { self?.onShowWelcome?() }
        })
        items.append(command("cmd:quit", "Quit Lodestar", subtitle: "Lodestar", symbol: "power") {
            NSApp.terminate(nil); return .close
        })
        return items
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
