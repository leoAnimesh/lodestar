import Foundation
import CoreGraphics

/// Light/dark appearance choice, stored as `"appearance"` in config.json.
public enum AppearanceMode: String, CaseIterable, Sendable {
    case system, light, dark

    public init(configValue: String?) { self = configValue.flatMap(AppearanceMode.init(rawValue:)) ?? .system }
    /// nil for the default, so config.json stays minimal.
    public var configValue: String? { self == .system ? nil : rawValue }

    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Where the launcher panel opens, stored as `"launcherPosition"`.
public enum LauncherPosition: String, CaseIterable, Sendable {
    /// Horizontally centered, its center at ~68% of the screen height (the default).
    case upperThird
    /// Centered on the screen.
    case center

    public init(configValue: String?) { self = configValue.flatMap(LauncherPosition.init(rawValue:)) ?? .upperThird }
    public var configValue: String? { self == .upperThird ? nil : rawValue }

    public var title: String {
        switch self {
        case .upperThird: return "Upper Third"
        case .center: return "Center"
        }
    }

    /// Bottom-left origin (Cocoa coordinates) for a panel of `size` on a
    /// screen whose visible frame is `visible`. Never places it off-screen.
    public func origin(panelSize size: CGSize, visibleFrame visible: CGRect) -> CGPoint {
        let x = visible.midX - size.width / 2
        let centerY: CGFloat
        switch self {
        case .upperThird: centerY = visible.minY + visible.height * 0.68
        case .center: centerY = visible.midY
        }
        var y = centerY - size.height / 2
        y = min(y, visible.maxY - size.height)
        y = max(y, visible.minY)
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}

/// Well-known system shortcuts that usually win over a Carbon hotkey, so
/// registering them "succeeds" but the launcher never opens.
public enum HotkeyConflicts {
    public static func systemConflict(for spec: HotkeySpec) -> String? {
        let c = HotkeySpec.command, o = HotkeySpec.option, ctl = HotkeySpec.control
        switch (spec.keyCode, spec.carbonModifiers) {
        case (49, c):
            return "⌘Space opens Spotlight. To use it here, first turn off Spotlight's shortcut in System Settings › Keyboard › Keyboard Shortcuts › Spotlight."
        case (49, c | o):
            return "⌥⌘Space opens a Finder search window. Turn that shortcut off in System Settings › Keyboard › Keyboard Shortcuts › Spotlight to use it here."
        case (49, ctl), (49, ctl | o):
            return "\(spec) switches input sources. Turn it off in System Settings › Keyboard › Keyboard Shortcuts › Input Sources to use it here."
        case (48, c):
            return "⌘Tab is the app switcher and can't be used."
        default:
            return nil
        }
    }
}

/// First-run onboarding bookkeeping kept in UserDefaults.
public enum Onboarding {
    /// Bump when the flow changes enough that everyone should see it again.
    /// 2: the permissions step became required, and the flag now only records
    /// a flow that was actually finished.
    public static let currentVersion = 2
    public static let completedVersionKey = "onboarding.completedVersion"
    /// Written by v0.1.1, which also recorded it when the window was merely
    /// closed (or dismissed by a dev run), so its value proves nothing. Ignored
    /// and deleted.
    public static let untrustedCompletedVersionKey = "onboardingCompletedVersion"
    /// Set by builds before onboarding existed, when the launcher was shown on first launch.
    public static let legacyFirstLaunchKey = "didShowFirstLaunch"
    /// When the "permission missing" reminder last opened, to keep it gentle.
    public static let lastPermissionReminderKey = "onboarding.lastPermissionReminder"
    /// At most one reminder per this interval (and never more than once per launch).
    public static let reminderInterval: TimeInterval = 24 * 60 * 60

    public enum Action: Equatable, Sendable {
        case none
        /// Open the welcome window from the first step.
        case welcome
        /// Open the welcome window on the permissions step.
        case permissions
    }

    public struct Decision: Equatable, Sendable {
        public var action: Action
        /// The value to store for `completedVersionKey` (nil = leave as is).
        public var storeCompletedVersion: Int?
        /// Whether to delete the legacy key.
        public var removeLegacyKey: Bool
        /// Whether to record "now" as the last permission reminder.
        public var recordReminder: Bool

        public var showOnboarding: Bool { action != .none }
    }

    /// Decides what to do at launch.
    ///
    /// - Fresh install (nothing stored): the full welcome flow, always.
    /// - Only the legacy `didShowFirstLaunch` flag: that build had no
    ///   onboarding, so this person never saw the permission steps. If
    ///   Accessibility is already granted they're set up and silently marked
    ///   done; otherwise they get the flow once, starting at permissions.
    /// - Completed an older flow version: shown again.
    /// - Completed the current version but Accessibility is missing: a
    ///   reminder (the permissions step), at most once a day.
    public static func launchDecision(completedVersion: Int?,
                                      legacyDidShowFirstLaunch: Bool,
                                      accessibilityGranted: Bool,
                                      lastReminder: Date? = nil,
                                      now: Date = Date(),
                                      forceShow: Bool = false) -> Decision {
        func decision(_ action: Action, store: Int? = nil, reminder: Bool = false) -> Decision {
            let willBeCompleted = (store ?? completedVersion) != nil
            return Decision(action: action, storeCompletedVersion: store,
                            removeLegacyKey: legacyDidShowFirstLaunch && willBeCompleted,
                            recordReminder: reminder)
        }
        if forceShow { return decision(.welcome) }
        if let completed = completedVersion {
            if completed < currentVersion { return decision(.welcome) }
            if !accessibilityGranted {
                let due = lastReminder.map { now.timeIntervalSince($0) >= reminderInterval || $0 > now } ?? true
                if due { return decision(.permissions, reminder: true) }
            }
            return decision(.none)
        }
        if legacyDidShowFirstLaunch {
            return accessibilityGranted ? decision(.none, store: currentVersion) : decision(.permissions)
        }
        return decision(.welcome)
    }
}

extension HotkeySpec {
    /// One label per key for keycap-style display, e.g. ["⌃", "⌥", "Space"].
    public var keycapParts: [String] {
        HotkeySpec.modifierSymbols(carbonModifiers).map(String.init)
            + [HotkeySpec.displayName(forKeyCode: keyCode, fallback: keyName)]
    }
}
