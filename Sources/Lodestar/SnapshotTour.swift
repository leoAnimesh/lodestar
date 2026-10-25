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
            var sample = ColorHistory()
            let now = Date()
            // Oldest first, so #3A7BFF ends up newest.
            for (i, hex) in ["#1F6FEB", "#E5484D", "#30A46C", "#F5A524", "#8E4EC6", "#3A7BFF"].enumerated() {
                if let c = SRGBColor(hex: hex) { sample.add(c, at: now.addingTimeInterval(Double(i - 6) * 3700 + 120)) }
            }
            app.showPanel(pushing: ColorHistoryScreen(picker: ColorPicker(storeURL: nil, history: sample)))
            return app.launcherWindow
        }))
        states.append(("launcher-12-actions-popover", {
            app.showPanel(query: "cal")
            app.openActionPopover()
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
        run(0)
    }

    /// Clipboard History with one sample entry of each type, held in memory
    /// (images in a temp folder); the user's real history is never read or written.
    private func appendClipboardStates(prefix: String, full: Bool) {
        guard let app else { return }
        var steps: [(String, String, Bool, Bool)] = [  // name, entry title, actions, filter menu
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
                if actions { app.openActionPopover() }
                if filter { app.openFilterMenu() }
                return app.launcherWindow
            }))
        }
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
            self.announce(state.name, window.windowNumber)
            self.waitForCapture(state.name, deadline: Date().addingTimeInterval(15)) { self.run(index + 1) }
        }
    }

    private func announce(_ name: String, _ windowID: Int) {
        let url = output.appendingPathComponent("manifest.txt")
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        handle.seekToEndOfFile()
        handle.write(Data("\(name) \(windowID)\n".utf8))
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
