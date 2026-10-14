import XCTest
@testable import LodestarCore

final class CommandPreferencesTests: XCTestCase {
    func testEnableDisableDropsDefaults() {
        var prefs = CommandPreferences()
        XCTAssertTrue(prefs.isEnabled("cmd:files"))
        prefs.setEnabled(false, for: "cmd:files")
        XCTAssertFalse(prefs.isEnabled("cmd:files"))
        XCTAssertEqual(prefs.configValue, ["cmd:files": CommandSettings(enabled: false)])
        prefs.setEnabled(true, for: "cmd:files")
        XCTAssertTrue(prefs.isEnabled("cmd:files"))
        XCTAssertNil(prefs.configValue, "an entry back at its defaults is removed")
        XCTAssertEqual(prefs.enabledOnly(["a", "cmd:files", "b"], id: { $0 }), ["a", "cmd:files", "b"])
        prefs.setEnabled(false, for: "a")
        XCTAssertEqual(prefs.enabledOnly(["a", "cmd:files", "b"], id: { $0 }), ["cmd:files", "b"])
    }

    func testInitDropsDefaultEntries() {
        let prefs = CommandPreferences(["x": CommandSettings(enabled: true), "y": CommandSettings(alias: "yy")])
        XCTAssertEqual(prefs.entries.keys.sorted(), ["y"])
    }

    func testAliasNormalizationAndValidation() throws {
        XCTAssertEqual(try CommandPreferences.normalizeAlias("  CH "), "ch")
        XCTAssertNil(try CommandPreferences.normalizeAlias("   "))
        XCTAssertNil(try CommandPreferences.normalizeAlias(nil))
        XCTAssertThrowsError(try CommandPreferences.normalizeAlias("two words")) {
            XCTAssertEqual($0 as? AliasError, .containsWhitespace)
        }
        XCTAssertThrowsError(try CommandPreferences.normalizeAlias(String(repeating: "a", count: 25))) {
            XCTAssertEqual($0 as? AliasError, .tooLong(max: 24))
        }
    }

    func testAliasConflictsAndLookup() throws {
        var prefs = CommandPreferences()
        try prefs.setAlias("ch", for: "cmd:clipboard")
        XCTAssertEqual(prefs.alias(for: "cmd:clipboard"), "ch")
        XCTAssertEqual(prefs.commandID(forAlias: " CH "), "cmd:clipboard")
        XCTAssertThrowsError(try prefs.setAlias("ch", for: "cmd:files")) {
            XCTAssertEqual($0 as? AliasError, .inUse(byCommandID: "cmd:clipboard"))
        }
        // Re-setting your own alias is fine; clearing removes the entry.
        try prefs.setAlias("CH", for: "cmd:clipboard")
        try prefs.setAlias("", for: "cmd:clipboard")
        XCTAssertNil(prefs.commandID(forAlias: "ch"))
        XCTAssertNil(prefs.configValue)
    }

    func testAliasPromotion() throws {
        var prefs = CommandPreferences()
        try prefs.setAlias("wl", for: "wm:Left Half")
        let available: Set = ["wm:Left Half", "app:/A", "app:/B"]
        XCTAssertEqual(prefs.promotingAlias(of: "wl", in: ["app:/A", "wm:Left Half"], available: available),
                       ["wm:Left Half", "app:/A"])
        // Inserted even when fuzzy ranking didn't find it.
        XCTAssertEqual(prefs.promotingAlias(of: "WL", in: ["app:/B"], available: available), ["wm:Left Half", "app:/B"])
        // Disabled commands don't answer to their alias.
        prefs.setEnabled(false, for: "wm:Left Half")
        XCTAssertEqual(prefs.promotingAlias(of: "wl", in: ["app:/B"], available: available), ["app:/B"])
        XCTAssertEqual(prefs.alias(for: "wm:Left Half"), "wl", "disabling keeps the alias")
    }

    func testHotkeysAndConflicts() throws {
        var prefs = CommandPreferences()
        let left = HotkeySpec("ctrl+option+left")!
        try prefs.setHotkey(left, for: "wm:Left Half", launcherHotkey: .default)
        XCTAssertEqual(prefs.hotkey(for: "wm:Left Half"), left)
        XCTAssertEqual(prefs.settings(for: "wm:Left Half").hotkey, "ctrl+option+left")
        XCTAssertThrowsError(try prefs.setHotkey(HotkeySpec("option+ctrl+left"), for: "wm:Right Half", launcherHotkey: .default)) {
            XCTAssertEqual($0 as? CommandHotkeyError, .inUse(byCommandID: "wm:Left Half"))
        }
        XCTAssertThrowsError(try prefs.setHotkey(.default, for: "wm:Right Half", launcherHotkey: .default)) {
            XCTAssertEqual($0 as? CommandHotkeyError, .sameAsLauncher)
        }
        try prefs.setHotkey(HotkeySpec("ctrl+option+right"), for: "wm:Right Half", launcherHotkey: .default)
        XCTAssertEqual(prefs.hotkeyBindings.map(\.id), ["wm:Left Half", "wm:Right Half"])
        prefs.setEnabled(false, for: "wm:Right Half")
        XCTAssertEqual(prefs.hotkeyBindings.map(\.id), ["wm:Left Half"], "disabled commands get no shortcut")
        try prefs.setHotkey(nil, for: "wm:Left Half", launcherHotkey: .default)
        XCTAssertNil(prefs.hotkey(for: "wm:Left Half"))
    }

    func testPrune() throws {
        var prefs = CommandPreferences()
        try prefs.setAlias("x", for: "script:/gone.sh")
        prefs.setEnabled(false, for: "cmd:files")
        XCTAssertEqual(prefs.prune(keeping: ["cmd:files"]), ["script:/gone.sh"])
        XCTAssertEqual(prefs.entries.keys.sorted(), ["cmd:files"])
    }

    func testRoundTripsThroughConfigFile() throws {
        var prefs = CommandPreferences()
        prefs.setEnabled(false, for: "sys:sleep")
        try prefs.setAlias("cb", for: "cmd:clipboard")
        try prefs.setHotkey(HotkeySpec("ctrl+option+return"), for: "wm:Maximize", launcherHotkey: .default)
        let existing = Data(#"{"hotkey":"cmd+shift+space","custom":1}"#.utf8)
        let (data, config) = try LodestarConfig.updated(existing) { $0.commandPreferences = prefs }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["custom"] as? Int, 1)
        let commands = try XCTUnwrap(object["commands"] as? [String: [String: Any]])
        XCTAssertEqual(commands["sys:sleep"]?["enabled"] as? Bool, false)
        XCTAssertEqual(commands["cmd:clipboard"]?["alias"] as? String, "cb")
        XCTAssertEqual(commands["wm:Maximize"]?["hotkey"] as? String, "ctrl+option+return")
        let decoded = try JSONDecoder().decode(LodestarConfig.self, from: data)
        XCTAssertEqual(decoded.commandPreferences, prefs)
        XCTAssertEqual(config.commandPreferences, prefs)
        // Clearing everything removes the key.
        let (cleared, _) = try LodestarConfig.updated(data) { $0.commandPreferences = CommandPreferences() }
        let clearedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: cleared) as? [String: Any])
        XCTAssertNil(clearedObject["commands"])
        XCTAssertEqual(clearedObject["hotkey"] as? String, "cmd+shift+space")
    }

    func testCatalogSectionsFilterAndGroup() throws {
        let all = [
            CommandDescriptor(id: "cmd:clipboard", title: "Clipboard History", kind: .command, group: "Lodestar", keywords: ["paste"]),
            CommandDescriptor(id: "cmd:files", title: "Search Files", kind: .command, group: "Lodestar"),
            CommandDescriptor(id: "wm:Left Half", title: "Left Half", kind: .window, group: "Window Management"),
            CommandDescriptor(id: "wm:Maximize", title: "Maximize", kind: .window, group: "Window Management"),
            CommandDescriptor(id: "script:/ip.sh", title: "Show IP Address", kind: .script, group: "Script Commands"),
        ]
        XCTAssertEqual(CommandCatalog.sections(all, query: "").map(\.title), ["Lodestar", "Window Management", "Script Commands"])
        XCTAssertEqual(CommandCatalog.sections(all, query: "", kind: .window).flatMap(\.commands).map(\.id), ["wm:Left Half", "wm:Maximize"])
        XCTAssertEqual(CommandCatalog.sections(all, query: "paste").flatMap(\.commands).map(\.id), ["cmd:clipboard"])
        // Group names match too, so "window" lists the whole section.
        XCTAssertEqual(CommandCatalog.sections(all, query: "window management").flatMap(\.commands).count, 2)
        var prefs = CommandPreferences()
        try prefs.setAlias("zz", for: "cmd:files")
        XCTAssertEqual(CommandCatalog.sections(all, query: "zz", preferences: prefs).flatMap(\.commands).map(\.id), ["cmd:files"])
        XCTAssertTrue(CommandCatalog.sections(all, query: "qqqq").isEmpty)
    }
}

final class AppPreferencesTests: XCTestCase {
    func testAppearanceAndPositionConfigValues() {
        XCTAssertEqual(AppearanceMode(configValue: nil), .system)
        XCTAssertEqual(AppearanceMode(configValue: "dark"), .dark)
        XCTAssertEqual(AppearanceMode(configValue: "purple"), .system)
        XCTAssertNil(AppearanceMode.system.configValue)
        XCTAssertEqual(AppearanceMode.light.configValue, "light")
        XCTAssertEqual(LauncherPosition(configValue: nil), .upperThird)
        XCTAssertEqual(LauncherPosition(configValue: "center"), .center)
        XCTAssertNil(LauncherPosition.upperThird.configValue)
    }

    func testLauncherOrigin() {
        let visible = CGRect(x: 0, y: 40, width: 1000, height: 800)
        let size = CGSize(width: 700, height: 440)
        XCTAssertEqual(LauncherPosition.center.origin(panelSize: size, visibleFrame: visible), CGPoint(x: 150, y: 220))
        // 40 + 800 * 0.68 - 220 = 364
        XCTAssertEqual(LauncherPosition.upperThird.origin(panelSize: size, visibleFrame: visible), CGPoint(x: 150, y: 364))
        // A short screen keeps the panel fully visible.
        let short = CGRect(x: 0, y: 0, width: 800, height: 460)
        let origin = LauncherPosition.upperThird.origin(panelSize: size, visibleFrame: short)
        XCTAssertEqual(origin.y, 20)
    }

    func testWindowGap() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(WindowGap.apply(0, to: CGRect(x: 0, y: 0, width: 500, height: 800), in: visible),
                       CGRect(x: 0, y: 0, width: 500, height: 800))
        // Left half: full gap at screen edges, half at the shared middle edge.
        XCTAssertEqual(WindowGap.apply(10, to: CGRect(x: 0, y: 0, width: 500, height: 800), in: visible),
                       CGRect(x: 10, y: 10, width: 485, height: 780))
        XCTAssertEqual(WindowGap.apply(10, to: CGRect(x: 500, y: 0, width: 500, height: 800), in: visible),
                       CGRect(x: 505, y: 10, width: 485, height: 780))
        XCTAssertEqual(WindowGap.clamp(100), 32)
        XCTAssertEqual(WindowGap.clamp(-3), 0)
        XCTAssertEqual(WindowGap.clamp(nil), 0)
    }

    func testSystemHotkeyConflicts() {
        XCTAssertNotNil(HotkeyConflicts.systemConflict(for: HotkeySpec("cmd+space")!))
        XCTAssertTrue(HotkeyConflicts.systemConflict(for: HotkeySpec("cmd+space")!)!.contains("Spotlight"))
        XCTAssertNotNil(HotkeyConflicts.systemConflict(for: HotkeySpec("ctrl+space")!))
        XCTAssertNil(HotkeyConflicts.systemConflict(for: .default))
        XCTAssertNil(HotkeyConflicts.systemConflict(for: HotkeySpec("cmd+shift+space")!))
    }

    func testKeycapParts() {
        XCTAssertEqual(HotkeySpec.default.keycapParts, ["⌥", "Space"])
        XCTAssertEqual(HotkeySpec("shift+cmd+k")!.keycapParts, ["⇧", "⌘", "K"])
    }

    func testOnboardingLaunchDecision() {
        // Fresh install: show it.
        XCTAssertEqual(Onboarding.launchDecision(completedVersion: nil, legacyDidShowFirstLaunch: false),
                       .init(showOnboarding: true, storeCompletedVersion: nil, removeLegacyKey: false))
        // Upgraded from a build that showed the launcher on first run: migrate silently.
        XCTAssertEqual(Onboarding.launchDecision(completedVersion: nil, legacyDidShowFirstLaunch: true),
                       .init(showOnboarding: false, storeCompletedVersion: 1, removeLegacyKey: true))
        // Already completed.
        XCTAssertEqual(Onboarding.launchDecision(completedVersion: 1, legacyDidShowFirstLaunch: false).showOnboarding, false)
        // A completed version wins over the legacy flag, which is still cleaned up.
        XCTAssertEqual(Onboarding.launchDecision(completedVersion: 1, legacyDidShowFirstLaunch: true),
                       .init(showOnboarding: false, storeCompletedVersion: nil, removeLegacyKey: true))
        // Explicit request (--onboarding or "Show Welcome…").
        XCTAssertTrue(Onboarding.launchDecision(completedVersion: 1, legacyDidShowFirstLaunch: false, forceShow: true).showOnboarding)
    }
}
