import AppKit
import LodestarCore

/// Launcher commands for Caffeinate / Decaffeinate (registered by RootScreen).
/// While a session runs, Decaffeinate leads and shows the time left; while
/// idle, Decaffeinate is hidden from search (it still appears in Settings).
enum CaffeinateCommands {
    static let decaffeinateID = "cmd:decaffeinate"
    static var allIDs: [String] { CaffeinateDuration.presets.map(\.commandID) + [decaffeinateID] }

    static let summaries: [String: String] = {
        var s: [String: String] = [:]
        for d in CaffeinateDuration.presets {
            s[d.commandID] = d.seconds == nil
                ? "Keeps your Mac and its display awake until you run Decaffeinate or quit Lodestar."
                : "Keeps your Mac and its display awake, then lets it sleep normally again."
        }
        s[decaffeinateID] = "Stops Caffeinate so your Mac can sleep again. Only listed in search while Caffeinate is on."
        return s
    }()

    static func items(_ caffeinator: Caffeinator) -> [LauncherItem] {
        let status = caffeinator.statusText
        var items = CaffeinateDuration.presets.map { duration -> LauncherItem in
            LauncherItem(
                id: duration.commandID, title: duration.commandTitle,
                // While active, Decaffeinate carries the status; variants just say what they'd do.
                subtitle: status != nil ? "Replaces the current session" : (duration.seconds == nil ? "Keep the Mac awake" : nil),
                icon: .symbol("cup.and.saucer"), accessory: "Command",
                keywords: ["awake", "keep awake", "prevent sleep", "no sleep", "coffee", "caffeine", "amphetamine", "display"],
                actions: [LauncherAction(duration.commandTitle, symbol: "cup.and.saucer") {
                    guard caffeinator.start(duration) else { return .toast("macOS didn't allow keeping the Mac awake") }
                    let text = duration.seconds == nil ? "Caffeinated until stopped" : "Caffeinated — \(caffeinator.statusText?.replacingOccurrences(of: "Active — ", with: "") ?? "")"
                    return .closeThen { HUD.show(text, symbol: "cup.and.saucer.fill") }
                }])
        }
        items.append(LauncherItem(
            id: decaffeinateID, title: "Decaffeinate", subtitle: status ?? "Not active",
            icon: .symbol("cup.and.saucer.fill"), accessory: "Command",
            keywords: ["sleep", "allow sleep", "stop caffeinate", "decaf", "coffee", "caffeine"],
            actions: [LauncherAction("Decaffeinate", symbol: "moon.zzz") {
                guard caffeinator.isActive else { return .toast("Caffeinate isn't on") }
                caffeinator.stop()
                return .closeThen { HUD.show("Decaffeinated — your Mac can sleep", symbol: "moon.zzz") }
            }]))
        return items
    }

    /// Applies the visibility/ordering rule to a list of root results.
    static func arrange(_ items: [LauncherItem], active: Bool) -> [LauncherItem] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return CaffeinateState.arrange(items.map(\.id), active: active, decaffeinateID: decaffeinateID).compactMap { byID[$0] }
    }
}
