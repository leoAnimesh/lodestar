import Foundation

/// A parsed global shortcut such as "option+space" or "cmd+shift+k".
///
/// Values are expressed as Carbon virtual key codes and Carbon modifier
/// masks so the app target can hand them straight to RegisterEventHotKey,
/// while this module stays free of Carbon/AppKit.
public struct HotkeySpec: Equatable, Sendable, CustomStringConvertible {
    public let keyCode: UInt32
    public let carbonModifiers: UInt32
    public let keyName: String

    // Carbon modifier masks (Events.h): cmdKey, shiftKey, optionKey, controlKey.
    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    public static let `default` = HotkeySpec(keyCode: 49, carbonModifiers: option, keyName: "space")

    public init(keyCode: UInt32, carbonModifiers: UInt32, keyName: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyName = keyName
    }

    public init?(_ string: String) {
        let parts = string.lowercased()
            .split(whereSeparator: { $0 == "+" || $0 == "-" || $0 == " " })
            .map(String.init)
        guard let key = parts.last, let code = HotkeySpec.keyCodes[key] else { return nil }
        var mods: UInt32 = 0
        for m in parts.dropLast() {
            switch m {
            case "cmd", "command", "⌘": mods |= HotkeySpec.command
            case "shift", "⇧": mods |= HotkeySpec.shift
            case "opt", "option", "alt", "⌥": mods |= HotkeySpec.option
            case "ctrl", "control", "⌃": mods |= HotkeySpec.control
            default: return nil
            }
        }
        // A global hotkey without modifiers would swallow normal typing.
        guard mods != 0 || key.hasPrefix("f") && key.count > 1 else { return nil }
        self.init(keyCode: code, carbonModifiers: mods, keyName: key)
    }

    public var description: String {
        var s = ""
        if carbonModifiers & HotkeySpec.control != 0 { s += "⌃" }
        if carbonModifiers & HotkeySpec.option != 0 { s += "⌥" }
        if carbonModifiers & HotkeySpec.shift != 0 { s += "⇧" }
        if carbonModifiers & HotkeySpec.command != 0 { s += "⌘" }
        return s + (keyName == "space" ? "Space" : keyName.uppercased())
    }

    /// ANSI US-layout virtual key codes (HIToolbox Events.h, kVK_*).
    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
        "escape": 53, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]
}
