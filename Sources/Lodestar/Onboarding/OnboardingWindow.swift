import AppKit
import SwiftUI
import LodestarCore

enum OnboardingStep: Int, CaseIterable {
    case welcome, hotkey, permissions, startup, tour, done

    var primaryTitle: String {
        switch self {
        case .welcome: return "Get Started"
        case .done: return "Open Lodestar"
        default: return "Continue"
        }
    }
}

final class OnboardingState: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    /// +1 when moving forward, -1 when moving back (for the slide direction).
    @Published private(set) var direction = 1
    /// Selected feature in the tour step (TourStep.Feature raw value).
    @Published var tourFeature = 0
    /// Whether the tour's mini launcher shows its ⌘K action panel.
    @Published var tourShowActions = false

    var isFirst: Bool { step == .welcome }
    var isLast: Bool { step == .done }

    func next() {
        guard let s = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        direction = 1
        step = s
    }

    func back() {
        guard let s = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        direction = -1
        step = s
    }

    func go(to s: OnboardingStep) {
        direction = s.rawValue >= step.rawValue ? 1 : -1
        step = s
    }
}

/// The welcome window: a centered, vibrant, fixed-size window that walks
/// through setup. Completion (or closing it) is recorded in UserDefaults.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 760, height: 540)

    let model: SettingsModel
    let state = OnboardingState()
    /// Called after the user finishes or closes the window.
    var onFinish: ((_ openLauncher: Bool) -> Void)?
    private var watching = false
    private var finishing = false

    private(set) lazy var window: NSWindow = {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: OnboardingWindowController.size),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Welcome to Lodestar"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        let hosting = NSHostingView(rootView: OnboardingView(model: model, state: state) { [weak self] in
            self?.finish(openLauncher: true)
        })
        // The window has a fixed size; don't let SwiftUI's ideal size resize it.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(OnboardingWindowController.size)
        window.center()
        return window
    }()

    init(model: SettingsModel) {
        self.model = model
    }

    func show(step: OnboardingStep = .welcome) {
        model.refresh()
        state.go(to: step)
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        if !watching { watching = true; model.permissions.startWatching() }
    }

    static func markCompleted() {
        UserDefaults.standard.set(Onboarding.currentVersion, forKey: Onboarding.completedVersionKey)
    }

    private func finish(openLauncher: Bool) {
        finishing = true
        OnboardingWindowController.markCompleted()
        window.close()
        finishing = false
        onFinish?(openLauncher)
    }

    func windowWillClose(_ notification: Notification) {
        model.capture.cancel()
        if watching { watching = false; model.permissions.stopWatching() }
        // Closing early counts as "seen": it isn't shown again automatically,
        // and "Show Welcome…" in the menu brings it back.
        if !finishing {
            OnboardingWindowController.markCompleted()
            onFinish?(false)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        model.capture.cancel()
    }
}
