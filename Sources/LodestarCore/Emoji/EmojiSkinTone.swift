import Foundation

/// The default skin tone for people and hand emoji, stored as
/// `"emojiSkinTone"` in config.json (missing = the default yellow).
public enum EmojiSkinTone: String, CaseIterable, Sendable {
    case none, light, mediumLight, medium, mediumDark, dark

    public init(configValue: String?) { self = configValue.flatMap(EmojiSkinTone.init(rawValue:)) ?? .none }
    public var configValue: String? { self == .none ? nil : rawValue }

    public var title: String {
        switch self {
        case .none: return "Default"
        case .light: return "Light"
        case .mediumLight: return "Medium-Light"
        case .medium: return "Medium"
        case .mediumDark: return "Medium-Dark"
        case .dark: return "Dark"
        }
    }

    /// The Fitzpatrick modifier (U+1F3FB…U+1F3FF), nil for `.none`.
    public var modifier: Unicode.Scalar? {
        switch self {
        case .none: return nil
        case .light: return "\u{1F3FB}"
        case .mediumLight: return "\u{1F3FC}"
        case .medium: return "\u{1F3FD}"
        case .mediumDark: return "\u{1F3FE}"
        case .dark: return "\u{1F3FF}"
        }
    }

    /// `glyph` in this tone. Inserts the modifier after each modifier base,
    /// dropping the U+FE0F that followed it, except a base joined by ZWJ on
    /// both sides (the handshake in 🧑‍🤝‍🧑). Mirrors `toned()` in
    /// scripts/generate-emoji-data.py, which only marks emoji whose toned forms
    /// built this way are all valid fully-qualified sequences.
    public func apply(to glyph: String, modifierBases: Set<UInt32>) -> String {
        guard let modifier else { return glyph }
        let scalars = Array(glyph.unicodeScalars)
        var out = String.UnicodeScalarView()
        var skipFE0F = false
        for (i, s) in scalars.enumerated() {
            if skipFE0F && s.value == 0xFE0F { skipFE0F = false; continue }
            skipFE0F = false
            out.append(s)
            let interior = i > 0 && i < scalars.count - 1 && scalars[i - 1].value == 0x200D && scalars[i + 1].value == 0x200D
            if modifierBases.contains(s.value) && !interior {
                out.append(modifier)
                skipFE0F = true
            }
        }
        return String(out)
    }
}

extension EmojiCatalog {
    /// The glyph to insert for `item` with the user's default tone.
    public func glyph(for item: EmojiItem, tone: EmojiSkinTone) -> String {
        item.supportsSkinTones ? tone.apply(to: item.glyph, modifierBases: modifierBases) : item.glyph
    }
}
