import AppKit
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

    init(app: AppDelegate, output: URL) {
        self.app = app
        self.output = output
    }

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
        appendEmojiStates(prefix: "light-emoji")
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
            SnapshotTour.isRunning = false
            NSLog("Lodestar snapshot: done")
            try? Data("done\n".utf8).write(to: output.appendingPathComponent("done.txt"))
            return
        }
        let state = states[index]
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
