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
        try prefs.setAlias("wl", for: "sys:lock")
        let available: Set = ["sys:lock", "app:/A", "app:/B"]
        XCTAssertEqual(prefs.promotingAlias(of: "wl", in: ["app:/A", "sys:lock"], available: available),
                       ["sys:lock", "app:/A"])
        // Inserted even when fuzzy ranking didn't find it.
        XCTAssertEqual(prefs.promotingAlias(of: "WL", in: ["app:/B"], available: available), ["sys:lock", "app:/B"])
        // Disabled commands don't answer to their alias.
        prefs.setEnabled(false, for: "sys:lock")
        XCTAssertEqual(prefs.promotingAlias(of: "wl", in: ["app:/B"], available: available), ["app:/B"])
        XCTAssertEqual(prefs.alias(for: "sys:lock"), "wl", "disabling keeps the alias")
    }

    func testHotkeysAndConflicts() throws {
        var prefs = CommandPreferences()
        let left = HotkeySpec("ctrl+option+left")!
        try prefs.setHotkey(left, for: "sys:lock", launcherHotkey: .default)
        XCTAssertEqual(prefs.hotkey(for: "sys:lock"), left)
        XCTAssertEqual(prefs.settings(for: "sys:lock").hotkey, "ctrl+option+left")
        XCTAssertThrowsError(try prefs.setHotkey(HotkeySpec("option+ctrl+left"), for: "sys:displaysleep", launcherHotkey: .default)) {
            XCTAssertEqual($0 as? CommandHotkeyError, .inUse(byCommandID: "sys:lock"))
        }
        XCTAssertThrowsError(try prefs.setHotkey(.default, for: "sys:displaysleep", launcherHotkey: .default)) {
            XCTAssertEqual($0 as? CommandHotkeyError, .sameAsLauncher)
        }
        try prefs.setHotkey(HotkeySpec("ctrl+option+right"), for: "sys:displaysleep", launcherHotkey: .default)
        XCTAssertEqual(prefs.hotkeyBindings.map(\.id), ["sys:displaysleep", "sys:lock"])
        prefs.setEnabled(false, for: "sys:displaysleep")
        XCTAssertEqual(prefs.hotkeyBindings.map(\.id), ["sys:lock"], "disabled commands get no shortcut")
        try prefs.setHotkey(nil, for: "sys:lock", launcherHotkey: .default)
        XCTAssertNil(prefs.hotkey(for: "sys:lock"))
    }

    func testPrune() throws {
        var prefs = CommandPreferences()
        try prefs.setAlias("x", for: "script:/gone.sh")
        prefs.setEnabled(false, for: "cmd:files")
        XCTAssertEqual(prefs.prune(keeping: ["cmd:files"]), ["script:/gone.sh"])
        XCTAssertEqual(prefs.entries.keys.sorted(), ["cmd:files"])
    }

    func testRetiredWindowLayoutSettingsAreIgnored() throws {
        // Window management was removed; its saved settings must not crash
        // loading or keep a global shortcut registered.
        let file = Data(#"{"windowGap":8,"commands":{"wm:Left Half":{"hotkey":"ctrl+option+left","alias":"lh"},"cmd:files":{"enabled":false}},"custom":1}"#.utf8)
        let config = try JSONDecoder().decode(LodestarConfig.self, from: file)
        let prefs = config.commandPreferences
        XCTAssertEqual(prefs.entries.keys.sorted(), ["cmd:files"])
        XCTAssertTrue(prefs.hotkeyBindings.isEmpty)
        XCTAssertNil(prefs.commandID(forAlias: "lh"))
        // The next save drops the stale keys and keeps unknown ones.
        let (data, _) = try LodestarConfig.updated(file) { $0.commandPreferences = $0.commandPreferences }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["windowGap"])
        XCTAssertEqual((object["commands"] as? [String: Any])?.keys.sorted(), ["cmd:files"])
        XCTAssertEqual(object["custom"] as? Int, 1)
    }

    func testRoundTripsThroughConfigFile() throws {
        var prefs = CommandPreferences()
        prefs.setEnabled(false, for: "sys:sleep")
        try prefs.setAlias("cb", for: "cmd:clipboard")
        try prefs.setHotkey(HotkeySpec("ctrl+option+return"), for: "cmd:emoji", launcherHotkey: .default)
        let existing = Data(#"{"hotkey":"cmd+shift+space","custom":1}"#.utf8)
        let (data, config) = try LodestarConfig.updated(existing) { $0.commandPreferences = prefs }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["custom"] as? Int, 1)
        let commands = try XCTUnwrap(object["commands"] as? [String: [String: Any]])
        XCTAssertEqual(commands["sys:sleep"]?["enabled"] as? Bool, false)
        XCTAssertEqual(commands["cmd:clipboard"]?["alias"] as? String, "cb")
        XCTAssertEqual(commands["cmd:emoji"]?["hotkey"] as? String, "ctrl+option+return")
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
            CommandDescriptor(id: "sys:lock", title: "Lock Screen", kind: .system, group: "System"),
            CommandDescriptor(id: "sys:sleep", title: "Sleep", kind: .system, group: "System"),
            CommandDescriptor(id: "script:/ip.sh", title: "Show IP Address", kind: .script, group: "Script Commands"),
        ]
        XCTAssertEqual(CommandCatalog.sections(all, query: "").map(\.title), ["Lodestar", "System", "Script Commands"])
        XCTAssertEqual(CommandCatalog.sections(all, query: "", kind: .system).flatMap(\.commands).map(\.id), ["sys:lock", "sys:sleep"])
        XCTAssertEqual(CommandCatalog.sections(all, query: "paste").flatMap(\.commands).map(\.id), ["cmd:clipboard"])
        // Group names match too, so "system" lists the whole section.
        XCTAssertEqual(CommandCatalog.sections(all, query: "system").flatMap(\.commands).count, 2)
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
