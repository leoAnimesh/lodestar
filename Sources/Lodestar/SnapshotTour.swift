import AppKit
import SwiftUI
import LodestarCore

/// Developer aid behind `Lodestar --snapshot <dir>`: steps through every
/// onboarding step, Settings tab and a few launcher states so each can be
/// screenshotted. For each state it appends "<name> <windowID>" to
/// <dir>/manifest.txt and waits (up to 15 s) for <dir>/<name>.png to appear,
/// so an outside `screencapture -l <windowID>` loop can capture the real
/// window. It doesn't mark onboarding complete or change config.
final class SnapshotTour {
    static private(set) var isRunning = false

    private weak var app: AppDelegate?
    private let output: URL
    private var states: [(name: String, setup: () -> NSWindow?)] = []

    /// Only states whose name contains this run (plus housekeeping states);
    /// from `--snapshot-only <text>`.
    private let only: String?

    init(app: AppDelegate, output: URL, only: String? = nil) {
        self.app = app
        self.output = output
        self.only = only
    }

    /// Sample clipboard images live here, never in Application Support.
    static let scratchDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("lodestar-snapshot-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

    func start() {
        guard let app else { return }
        SnapshotTour.isRunning = true
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try? Data().write(to: output.appendingPathComponent("manifest.txt"))

        let onboarding = app.onboardingWindowController
        for step in OnboardingStep.allCases {
            if step == .tour {
                for feature in TourStep.Feature.allCases {
                    states.append(("onboarding-\(step.rawValue + 1)-tour-\(feature.rawValue + 1)", {
                        onboarding.show(step: .tour)
                        onboarding.state.tourFeature = feature.rawValue
                        onboarding.state.tourShowActions = feature == .actions
                        return onboarding.window
                    }))
                }
            } else {
                states.append(("onboarding-\(step.rawValue + 1)-\(step)", {
                    onboarding.state.tourShowActions = false
                    onboarding.show(step: step)
                    return onboarding.window
                }))
            }
        }
        states.append(("hide-onboarding", {
            onboarding.window.orderOut(nil)
            return nil
        }))
        for (index, tab) in SettingsTab.allCases.enumerated() {
            states.append(("settings-\(index + 1)-\(tab.rawValue)", {
                app.openSettings(tab: tab)
                return app.settingsWindowController.window
            }))
        }
        states.append(("hide-settings", {
            app.settingsWindowController.window.orderOut(nil)
            return nil
        }))
        for (name, query) in [("launcher-1-empty", ""), ("launcher-2-search", "cal"), ("launcher-3-calculator", "2^10 / 4"),
                              ("launcher-4-commands", "s"), ("launcher-5-alias", "lh"), ("launcher-6-emoji-inline", "rocket")] {
            states.append((name, {
                app.showPanel(query: query)
                return app.launcherWindow
            }))
        }
        appendEmojiStates(prefix: "emoji")
        // Color picker and caffeinate rows. Caffeinate really runs (30 min)
        // for a few states and is stopped again; the color history shown is
        // sample data kept in memory, never written to disk.
        states.append(("launcher-7-pick-color", {
            app.showPanel(query: "color")
            return app.launcherWindow
        }))
        states.append(("launcher-8-caffeinate", {
            app.caffeinator.stop()
            app.showPanel(query: "caff")
            return app.launcherWindow
        }))
        states.append(("launcher-9-decaffeinate-active", {
            app.caffeinator.start(.thirtyMinutes)
            app.showPanel(query: "caff")
            return app.launcherWindow
        }))
        states.append(("launcher-10-empty-caffeinated", {
            app.showPanel(query: "")
            return app.launcherWindow
        }))
        states.append(("menubar-caffeinated", {
            app.hidePanel()
            return app.statusItemWindow
        }))
        states.append(("stop-caffeinate", {
            app.caffeinator.stop()
            return nil
        }))
        states.append(("launcher-11-color-history", {
            app.showPanel(pushing: ColorHistoryScreen(picker: ColorPicker(storeURL: nil, history: SnapshotTour.sampleColors())))
            return app.launcherWindow
        }))
        states.append(("launcher-12-actions-popover", {
            app.showPanel(query: "cal")
            app.moveSelection(to: 1)
            app.openActionPopover()
            app.simulateBackgroundRefresh()
            return app.launcherWindow
        }))
        appendClipboardStates(prefix: "clipboard", full: true)
        // The same views forced to light appearance (config is not touched).
        let previous = NSApp.appearance
        states.append(("light-launcher-empty", {
            NSApp.appearance = NSAppearance(named: .aqua)
            app.showPanel(query: "")
            return app.launcherWindow
        }))
        states.append(("light-launcher-commands", {
            app.showPanel(query: "s")
            return app.launcherWindow
        }))
        states.append(("light-launcher-actions-popover", {
            app.showPanel(query: "cal")
            app.openActionPopover()
            return app.launcherWindow
        }))
        appendEmojiStates(prefix: "light-emoji")
        appendClipboardStates(prefix: "light-clipboard", full: false)
        states.append(("light-settings-extensions", {
            app.hidePanel()
            app.openSettings(tab: .extensions)
            return app.settingsWindowController.window
        }))
        states.append(("light-onboarding-tour", {
            app.settingsWindowController.window.orderOut(nil)
            onboarding.show(step: .tour)
            onboarding.state.tourFeature = TourStep.Feature.search.rawValue
            onboarding.state.tourShowActions = false
            return onboarding.window
        }))
        states.append(("restore-appearance", {
            onboarding.window.orderOut(nil)
            NSApp.appearance = previous
            return nil
        }))
        appendUpdateStates()
        appendHeroStates(previousAppearance: previous)
        run(0)
    }

    /// The Software Update window with a sample release (no network).
    private func appendUpdateStates() {
        guard let app else { return }
        let url = URL(string: "https://github.com/leoAnimesh/lodestar/releases")!
        let sample = GitHubRelease(
            tagName: "v0.2.0", version: SemanticVersion("0.2.0")!, name: "Lodestar 0.2.0",
            notes: "## What's new\n\n- **Snippets:** type a keyword to expand saved text\n- Clipboard pins now sync between windows\n- Faster app search on large Applications folders\n\n## Fixes\n\n- The launcher no longer flickers when switching Spaces",
            htmlURL: url, publishedAt: Date(), isDraft: false, isPrerelease: false,
            assets: [ReleaseAsset(name: "Lodestar-0.2.0.zip", downloadURL: url, size: 4_100_000),
                     ReleaseAsset(name: "SHA256SUMS.txt", downloadURL: url, size: 170)])
        let updates = UpdateManager.shared
        let steps: [(String, UpdateManager.Phase)] = [
            ("update-1-available", .available(sample)),
            ("update-2-downloading", .downloading(received: 2_600_000, total: 4_100_000)),
            ("update-3-up-to-date", .upToDate),
            ("update-4-failed", .failed("Lodestar-0.2.0.zip didn't match its published checksum, so it was not used. Nothing was changed.")),
        ]
        for (name, phase) in steps {
            states.append((name, {
                updates.presentSample(phase, release: phase == .upToDate ? nil : sample)
                return NSApp.windows.first { $0.title == "Software Update" && $0.isVisible }
            }))
        }
        states.append(("hide-update", {
            NSApp.windows.first { $0.title == "Software Update" }?.orderOut(nil)
            updates.presentSample(.idle, release: nil)
            return nil
        }))
    }

    /// Dark launcher windows over the hero gradient, for `--render-hero`.
    /// A borderless backdrop window sits just below the launcher so its
    /// translucency picks up the banner's colors.
    private var backdrop: NSWindow?

    private func appendHeroStates(previousAppearance: NSAppearance?) {
        guard let app else { return }
        let showBackdrop = { [weak self] in
            guard let self else { return }
            NSApp.appearance = NSAppearance(named: .darkAqua)
            app.useSampleColorHistory(true)
            if self.backdrop == nil {
                let frame = (app.launcherWindow.screen ?? NSScreen.main)?.frame ?? NSRect(x: 0, y: 0, width: 1600, height: 1000)
                let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.level = NSWindow.Level(rawValue: app.launcherWindow.level.rawValue - 1)
                window.ignoresMouseEvents = true
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: HeroBackground())
                self.backdrop = window
            }
            self.backdrop?.orderFrontRegardless()
        }
        let launcherQueries = [("hero-launcher", ""), ("hero-launcher-calculator", "2^10 / 4")]
        for (name, query) in launcherQueries {
            states.append((name, {
                showBackdrop()
                app.showPanel(query: query)
                return app.launcherWindow
            }))
        }
        states.append(("hero-clipboard", {
            showBackdrop()
            app.showPanel(pushing: ClipboardHistoryScreen(history: SnapshotTour.sampleClipboard()))
            app.selectItem(titled: "Image")
            return app.launcherWindow
        }))
        states.append(("hero-emoji", {
            showBackdrop()
            // A search, so the user's own Recently Used row isn't shown.
            app.showCommand("cmd:emoji", query: "heart", select: 0)
            return app.launcherWindow
        }))
        states.append(("hide-hero-backdrop", { [weak self] in
            app.hidePanel()
            self?.backdrop?.orderOut(nil)
            self?.backdrop = nil
            app.useSampleColorHistory(false)
            NSApp.appearance = previousAppearance
            return nil
        }))
    }

    /// Clipboard History with one sample entry of each type, held in memory
    /// (images in a temp folder); the user's real history is never read or written.
    private func appendClipboardStates(prefix: String, full: Bool) {
        guard let app else { return }
        var steps: [(String, String, Bool, Bool)] = [  // name, entry title, actions, filter menu
            // With actions, a background refresh runs after the popover opens:
            // the highlight, preview and popover must all stay on the entry.
            ("1-text", "func greet", false, false),
            ("2-image", "Image (1404×538)", false, false),
            ("3-actions", "Image (1404×538)", true, false),
            ("4-filter", "func greet", false, true),
        ]
        if full {
            steps += [("5-color", "#0C0D0E", false, false), ("6-link", "https://github.com/leoAnimesh/lodestar", false, false),
                      ("7-file", "hosts", false, false), ("8-text-actions", "func greet", true, false)]
        }
        for (suffix, title, actions, filter) in steps {
            states.append(("\(prefix)-\(suffix)", {
                if prefix.hasPrefix("light-") { NSApp.appearance = NSAppearance(named: .aqua) }
                app.showPanel(pushing: ClipboardHistoryScreen(history: SnapshotTour.sampleClipboard()))
                app.selectItem(titled: title)
                if actions { app.openActionPopover(); app.simulateBackgroundRefresh() }
                if filter { app.openFilterMenu() }
                return app.launcherWindow
            }))
        }
        if full {
            states.append(("\(prefix)-9-open-with", {
                app.showPanel(pushing: ClipboardHistoryScreen(history: SnapshotTour.sampleClipboard()))
                app.selectItem(titled: "hosts")
                app.openActionPopover()
                app.chooseAction(titled: "Open With…")
                return app.launcherWindow
            }))
        }
    }

    /// Six sample colors, oldest first, so #3A7BFF ends up newest.
    static func sampleColors() -> ColorHistory {
        var sample = ColorHistory()
        let now = Date()
        for (i, hex) in ["#1F6FEB", "#E5484D", "#30A46C", "#F5A524", "#8E4EC6", "#3A7BFF"].enumerated() {
            if let c = SRGBColor(hex: hex) { sample.add(c, at: now.addingTimeInterval(Double(i - 6) * 3700 + 120)) }
        }
        return sample
    }

    static func sampleClipboard() -> ClipboardHistory {
        let history = ClipboardHistory(limit: 300, storeURL: nil, filesDirectory: scratchDirectory)
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let today = now
        func add(_ text: String, _ kind: ClipboardKind? = nil, _ date: Date, _ app: String, _ bundle: String) {
            var entry = ClipboardEntry.text(text, date: date, sourceApp: app, sourceBundleID: bundle)
            if let kind { entry.kind = kind }
            history.insert(entry)
        }
        // Oldest first: each insert goes on top.
        add("Meeting notes: ship the clipboard redesign, then write the release notes.", nil,
            now.addingTimeInterval(-20 * 86_400), "Notes", "com.apple.Notes")
        add("ssh deploy@staging.example.com", nil, now.addingTimeInterval(-9 * 86_400), "Terminal", "com.apple.Terminal")
        if let pinned = history.entries.first { history.setPinned(true, id: pinned.id) }
        add("/private/etc/hosts", .file, now.addingTimeInterval(-3 * 86_400), "Finder", "com.apple.finder")
        add("https://github.com/leoAnimesh/lodestar", nil, startOfToday.addingTimeInterval(-3 * 3600), "Safari", "com.apple.Safari")
        add("#0C0D0E", nil, today.addingTimeInterval(-30 * 60), "Preview", "com.apple.Preview")
        if let png = sampleImagePNG() {
            history.insertImage(data: png, date: today.addingTimeInterval(-12 * 60), sourceApp: "Preview", sourceBundleID: "com.apple.Preview")
        }
        add("""
        func greet(_ name: String) -> String {
            // Copied from TextEdit
            return "Hello, \\(name)!"
        }
        """, nil, today.addingTimeInterval(-3 * 60), "TextEdit", "com.apple.TextEdit")
        return history
    }

    /// A 1404×538 banner drawn from Lodestar's own brand mark.
    static func sampleImagePNG() -> Data? {
        MainActor.assumeIsolated { renderSampleImage() }
    }

    @MainActor
    private static func renderSampleImage() -> Data? {
        let banner = ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.20), Color(red: 0.33, green: 0.20, blue: 0.62)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 40) {
                LodestarStarIcon(size: 220).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Lodestar").font(.system(size: 120, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("Clipboard history, now with images").font(.system(size: 40, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .frame(width: 1404, height: 538)
        let renderer = ImageRenderer(content: banner)
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return nil }
        return ClipboardImageProcessor.encodePNG(cg)
    }

    /// The emoji grid: browsing, a search, symbols, and the ⌘K actions.
    private func appendEmojiStates(prefix: String) {
        guard let app else { return }
        let steps: [(String, String, Int?, Bool)] = [
            ("1-grid", "", 3, false),
            ("2-search", "heart", nil, false),
            ("3-symbols", "arrow", 2, false),
            ("4-actions", "", 3, true),
        ]
        for (suffix, query, select, actions) in steps {
            states.append(("\(prefix)-\(suffix)", {
                app.showCommand("cmd:emoji", query: query, select: select, actions: actions)
                return app.launcherWindow
            }))
        }
    }

    private func run(_ index: Int) {
        guard index < states.count else {
            app?.hidePanel()
            try? FileManager.default.removeItem(at: SnapshotTour.scratchDirectory)
            SnapshotTour.isRunning = false
            NSLog("Lodestar snapshot: done")
            try? Data("done\n".utf8).write(to: output.appendingPathComponent("done.txt"))
            return
        }
        let state = states[index]
        let housekeeping = ["hide-", "stop-", "restore-"].contains { state.name.hasPrefix($0) }
        if let only, !housekeeping, !state.name.contains(only) {
            run(index + 1)
            return
        }
        guard let window = state.setup() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.run(index + 1) }
            return
        }
        // Let animations settle before announcing the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.announce(state.name, window.windowNumber, frame: window.frame)
            self.waitForCapture(state.name, deadline: Date().addingTimeInterval(15)) { self.run(index + 1) }
        }
    }

    /// Appends "<name> <windowID> <x,y,w,h>" (the frame in screencapture's
    /// top-left coordinates, for region captures that include what's behind).
    private func announce(_ name: String, _ windowID: Int, frame: NSRect) {
        let url = output.appendingPathComponent("manifest.txt")
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.maxY
        let rect = [frame.minX, primaryHeight - frame.maxY, frame.width, frame.height].map { String(Int($0.rounded())) }
        handle.seekToEndOfFile()
        handle.write(Data("\(name) \(windowID) \(rect.joined(separator: ","))\n".utf8))
        try? handle.close()
    }

    private func waitForCapture(_ name: String, deadline: Date, then next: @escaping () -> Void) {
        let png = output.appendingPathComponent("\(name).png")
        if FileManager.default.fileExists(atPath: png.path) || Date() > deadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: next)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.waitForCapture(name, deadline: deadline, then: next) }
    }
}
