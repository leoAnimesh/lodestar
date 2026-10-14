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
    static let allModifiers = command | shift | option | control

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

    /// Builds a spec from a key code captured by a recorder, using the
    /// canonical key name. Returns nil for keys the config format can't express.
    public init?(keyCode: UInt32, carbonModifiers: UInt32) {
        guard let name = HotkeySpec.canonicalNames[keyCode] else { return nil }
        self.init(keyCode: keyCode, carbonModifiers: carbonModifiers & HotkeySpec.allModifiers, keyName: name)
    }

    /// Symbol form for UI, e.g. "⌥Space" or "⇧⌘K".
    public var description: String {
        HotkeySpec.modifierSymbols(carbonModifiers) + HotkeySpec.displayName(forKeyCode: keyCode, fallback: keyName)
    }

    /// The form written to config.json, e.g. "option+space" or "shift+cmd+k".
    /// Always round-trips through `init?(_ string:)`.
    public var configString: String {
        var parts: [String] = []
        if carbonModifiers & HotkeySpec.control != 0 { parts.append("ctrl") }
        if carbonModifiers & HotkeySpec.option != 0 { parts.append("option") }
        if carbonModifiers & HotkeySpec.shift != 0 { parts.append("shift") }
        if carbonModifiers & HotkeySpec.command != 0 { parts.append("cmd") }
        parts.append(HotkeySpec.canonicalNames[keyCode] ?? keyName)
        return parts.joined(separator: "+")
    }

    /// Whether two specs describe the same physical shortcut, ignoring
    /// key-name aliases such as "esc" vs "escape".
    public func isSameShortcut(as other: HotkeySpec) -> Bool {
        keyCode == other.keyCode && carbonModifiers == other.carbonModifiers
    }

    /// Modifier glyphs in the standard macOS order: ⌃⌥⇧⌘.
    public static func modifierSymbols(_ carbonModifiers: UInt32) -> String {
        var s = ""
        if carbonModifiers & control != 0 { s += "⌃" }
        if carbonModifiers & option != 0 { s += "⌥" }
        if carbonModifiers & shift != 0 { s += "⇧" }
        if carbonModifiers & command != 0 { s += "⌘" }
        return s
    }

    /// Display label for a key, e.g. "Space", "K", "F5", "↩", "←".
    public static func displayName(forKeyCode keyCode: UInt32, fallback: String = "?") -> String {
        let name = canonicalNames[keyCode] ?? fallback
        return displaySymbols[name] ?? name.uppercased()
    }

    // MARK: Cocoa modifier flags

    // NSEvent.ModifierFlags raw values, mirrored here so this module stays AppKit-free.
    public static let cocoaShift: UInt = 1 << 17
    public static let cocoaControl: UInt = 1 << 18
    public static let cocoaOption: UInt = 1 << 19
    public static let cocoaCommand: UInt = 1 << 20

    /// Converts NSEvent modifier flags (raw value) to a Carbon modifier mask.
    /// Caps Lock, Fn and device-specific bits are ignored.
    public static func carbonModifiers(cocoaFlags: UInt) -> UInt32 {
        var mods: UInt32 = 0
        if cocoaFlags & cocoaCommand != 0 { mods |= command }
        if cocoaFlags & cocoaShift != 0 { mods |= shift }
        if cocoaFlags & cocoaOption != 0 { mods |= option }
        if cocoaFlags & cocoaControl != 0 { mods |= control }
        return mods
    }

    // MARK: Validation

    /// Checks a combo captured by the recorder. A global shortcut needs at
    /// least one of ⌘ ⌥ ⌃; Shift alone would hijack ordinary typing.
    public static func validate(keyCode: UInt32, carbonModifiers: UInt32) -> Result<HotkeySpec, HotkeyValidationError> {
        let mods = carbonModifiers & allModifiers
        guard let spec = HotkeySpec(keyCode: keyCode, carbonModifiers: mods) else {
            return .failure(.unsupportedKey(keyCode))
        }
        guard mods & ~shift != 0 else { return .failure(.needsModifier) }
        return .success(spec)
    }

    // MARK: Key tables

    /// ANSI US-layout virtual key codes (HIToolbox Events.h, kVK_*).
    /// "-" is a separator in the config syntax, so the minus key is "minus".
    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "minus": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
        "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
        "home": 115, "pageup": 116, "forwarddelete": 117, "end": 119, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    /// Aliases that are accepted when parsing but never written back.
    private static let aliases: Set<String> = ["enter", "backspace", "esc"]

    /// Key code -> the name `configString` writes.
    static let canonicalNames: [UInt32: String] = {
        var names: [UInt32: String] = [:]
        for (name, code) in keyCodes where !aliases.contains(name) { names[code] = name }
        return names
    }()

    private static let displaySymbols: [String: String] = [
        "space": "Space", "return": "↩", "tab": "⇥", "escape": "⎋", "delete": "⌫",
        "forwarddelete": "⌦", "minus": "-", "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟",
        "left": "←", "right": "→", "down": "↓", "up": "↑",
    ]
}

/// Why a recorded combo can't be used as the global shortcut.
public enum HotkeyValidationError: Error, Equatable, Sendable {
    case needsModifier
    case unsupportedKey(UInt32)

    public var message: String {
        switch self {
        case .needsModifier: return "Include ⌘, ⌥ or ⌃ (Shift alone isn't enough)."
        case .unsupportedKey: return "That key can't be used as a shortcut."
        }
    }
}

/// Decides what a key press means while the hotkey recorder is capturing.
public enum HotkeyRecorder {
    public enum Outcome: Equatable, Sendable {
        /// Esc: stop recording, keep the current shortcut.
        case cancel
        /// Delete / Forward Delete: restore the default shortcut.
        case restoreDefault
        /// A valid combo to apply.
        case record(HotkeySpec)
        /// Not usable; keep recording and show the reason.
        case invalid(HotkeyValidationError)
    }

    static let escapeKey: UInt32 = 53
    static let deleteKeys: Set<UInt32> = [51, 117]

    /// `cocoaFlags` is `NSEvent.modifierFlags.rawValue`.
    public static func interpret(keyCode: UInt32, cocoaFlags: UInt) -> Outcome {
        let mods = HotkeySpec.carbonModifiers(cocoaFlags: cocoaFlags)
        if mods == 0 && keyCode == escapeKey { return .cancel }
        if mods == 0 && deleteKeys.contains(keyCode) { return .restoreDefault }
        switch HotkeySpec.validate(keyCode: keyCode, carbonModifiers: mods) {
        case .success(let spec): return .record(spec)
        case .failure(let error): return .invalid(error)
        }
    }

    /// Live preview of held modifiers while recording, e.g. "⌃⌥".
    public static func modifierPreview(cocoaFlags: UInt) -> String {
        HotkeySpec.modifierSymbols(HotkeySpec.carbonModifiers(cocoaFlags: cocoaFlags))
    }
}
