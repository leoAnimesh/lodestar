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
    public static let currentVersion = 1
    public static let completedVersionKey = "onboardingCompletedVersion"
    /// Set by builds before onboarding existed, when the launcher was shown on first launch.
    public static let legacyFirstLaunchKey = "didShowFirstLaunch"

    public struct Decision: Equatable, Sendable {
        /// Whether to open the welcome window now.
        public var showOnboarding: Bool
        /// The value to store for `completedVersionKey` (nil = leave as is).
        public var storeCompletedVersion: Int?
        /// Whether to delete the legacy key.
        public var removeLegacyKey: Bool
    }

    /// Decides what to do at launch.
    ///
    /// Migration: someone with the legacy flag already ran Lodestar and found
    /// the launcher, so they're treated as having completed version 1 and are
    /// not interrupted; they can open the welcome window from the menu.
    public static func launchDecision(completedVersion: Int?, legacyDidShowFirstLaunch: Bool,
                                      forceShow: Bool = false) -> Decision {
        var completed = completedVersion
        var store: Int?
        if completed == nil && legacyDidShowFirstLaunch {
            completed = 1
            store = 1
        }
        let show = forceShow || (completed ?? 0) < currentVersion
        return Decision(showOnboarding: show, storeCompletedVersion: store, removeLegacyKey: legacyDidShowFirstLaunch)
    }
}

extension HotkeySpec {
    /// One label per key for keycap-style display, e.g. ["⌃", "⌥", "Space"].
    public var keycapParts: [String] {
        HotkeySpec.modifierSymbols(carbonModifiers).map(String.init)
            + [HotkeySpec.displayName(forKeyCode: keyCode, fallback: keyName)]
    }
}
