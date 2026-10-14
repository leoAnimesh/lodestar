import Foundation

/// A section of the emoji picker ("Smileys & People", "Arrows", ...).
public struct EmojiCategory: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case emoji, symbol }
    public let id: String
    public let name: String
    public let kind: Kind

    public init(id: String, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// One emoji or symbol. `glyph` is the default (yellow / untoned) form.
public struct EmojiItem: Hashable, Sendable {
    public let glyph: String
    /// Lowercase CLDR short name ("grinning face") or Unicode name.
    public let name: String
    public let keywords: [String]
    public let categoryIndex: Int
    /// Emoji version in tenths (Emoji 15.1 = 151); 0 for plain symbols.
    public let version: Int
    /// Emoji version (tenths) that added the skin-tone variants; nil when the
    /// emoji has none.
    public let skinToneVersion: Int?

    public init(glyph: String, name: String, keywords: [String] = [], categoryIndex: Int, version: Int = 0, skinToneVersion: Int? = nil) {
        self.glyph = glyph
        self.name = name
        self.keywords = keywords
        self.categoryIndex = categoryIndex
        self.version = version
        self.skinToneVersion = skinToneVersion
    }

    public var supportsSkinTones: Bool { skinToneVersion != nil }

    /// "grinning face" → "Grinning Face", "flag: Japan" → "Flag: Japan".
    public var displayName: String { EmojiItem.titleCase(name) }

    /// Code points of `text` as "U+1F44D U+1F3FD".
    public static func codePoints(of text: String) -> String {
        text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
    }

    /// Words left lowercase inside a title ("Face with Tears of Joy").
    static let minorWords: Set<String> = ["a", "an", "and", "as", "at", "by", "for", "from", "in", "into", "of", "on", "or", "the", "to", "with"]

    /// Title case that keeps small words lowercase (except the first word and
    /// after a colon) and leaves the rest of each word as CLDR spells it.
    static func titleCase(_ s: String) -> String {
        var words: [String] = []
        var capitalizeNext = true
        for word in s.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
            let bare = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "():,"))
            if !capitalizeNext && minorWords.contains(bare) {
                words.append(word)
            } else if let first = word.firstIndex(where: { $0.isLetter }) {
                words.append(word[..<first] + word[first].uppercased() + word[word.index(after: first)...])
            } else {
                words.append(word)
            }
            capitalizeNext = word.hasSuffix(":")
        }
        return words.joined(separator: " ")
    }
}

/// The bundled emoji and symbol data (see scripts/generate-emoji-data.py).
public struct EmojiCatalog: Sendable {
    public let categories: [EmojiCategory]
    public let items: [EmojiItem]
    /// Scalars that take a skin-tone modifier (Emoji_Modifier_Base).
    public let modifierBases: Set<UInt32>
    public let unicodeVersion: String
    public let cldrVersion: String

    /// Search tokens per item, parallel to `items`.
    let index: [EmojiSearch.Entry]
    private let byGlyph: [String: Int]

    public init(categories: [EmojiCategory], items: [EmojiItem], modifierBases: Set<UInt32> = [],
                unicodeVersion: String = "", cldrVersion: String = "") {
        self.categories = categories
        self.items = items
        self.modifierBases = modifierBases
        self.unicodeVersion = unicodeVersion
        self.cldrVersion = cldrVersion
        self.index = items.map(EmojiSearch.Entry.init)
        var byGlyph: [String: Int] = [:]
        for (i, item) in items.enumerated() where byGlyph[item.glyph] == nil { byGlyph[item.glyph] = i }
        self.byGlyph = byGlyph
    }

    /// The first item whose default glyph is `glyph` (FE0F/FE0E-insensitive).
    public func item(forGlyph glyph: String) -> EmojiItem? {
        if let i = byGlyph[glyph] { return items[i] }
        let stripped = EmojiCatalog.strippingVariationSelectors(glyph)
        if let i = byGlyph[stripped] { return items[i] }
        if let i = byGlyph[stripped + "\u{FE0F}"] { return items[i] }
        if let i = byGlyph[stripped + "\u{FE0E}"] { return items[i] }
        return items.first { EmojiCatalog.strippingVariationSelectors($0.glyph) == stripped }
    }

    public func items(in categoryIndex: Int) -> [EmojiItem] {
        items.filter { $0.categoryIndex == categoryIndex }
    }

    public func category(of item: EmojiItem) -> EmojiCategory? {
        categories.indices.contains(item.categoryIndex) ? categories[item.categoryIndex] : nil
    }

    /// Drops emoji newer than `maxVersion` (tenths), which the system font
    /// can't draw, and skin tones it can't draw. Symbols are always kept.
    public func available(upTo maxVersion: Int) -> EmojiCatalog {
        let kept = items.compactMap { item -> EmojiItem? in
            guard item.version <= maxVersion else { return nil }
            guard let tones = item.skinToneVersion, tones > maxVersion else { return item }
            return EmojiItem(glyph: item.glyph, name: item.name, keywords: item.keywords, categoryIndex: item.categoryIndex,
                             version: item.version, skinToneVersion: nil)
        }
        return EmojiCatalog(categories: categories, items: kept, modifierBases: modifierBases,
                            unicodeVersion: unicodeVersion, cldrVersion: cldrVersion)
    }

    static func strippingVariationSelectors(_ s: String) -> String {
        var scalars = String.UnicodeScalarView()
        for u in s.unicodeScalars where u.value != 0xFE0F && u.value != 0xFE0E { scalars.append(u) }
        return String(scalars)
    }

    // MARK: Loading

    private struct File: Decodable {
        struct Item: Decodable {
            let c: String
            let n: String
            let k: [String]?
            let g: Int
            let v: Int?
            let t: Int?
        }
        let unicodeVersion: String
        let cldrVersion: String
        let categories: [EmojiCategory]
        let modifierBases: [UInt32]
        let items: [Item]
    }

    public enum LoadError: Error, Equatable { case notFound, invalid(String) }

    public static func decode(_ data: Data) throws -> EmojiCatalog {
        let file: File
        do { file = try JSONDecoder().decode(File.self, from: data) } catch { throw LoadError.invalid(String(describing: error)) }
        let items = file.items.compactMap { raw -> EmojiItem? in
            guard file.categories.indices.contains(raw.g) else { return nil }
            return EmojiItem(glyph: raw.c, name: raw.n, keywords: raw.k ?? [], categoryIndex: raw.g, version: raw.v ?? 0, skinToneVersion: raw.t)
        }
        return EmojiCatalog(categories: file.categories, items: items, modifierBases: Set(file.modifierBases),
                            unicodeVersion: file.unicodeVersion, cldrVersion: file.cldrVersion)
    }

    /// Loads the copy of emoji.json bundled with LodestarCore.
    public static func loadBundled() throws -> EmojiCatalog {
        guard let url = bundledDataURL() else { throw LoadError.notFound }
        return try decode(Data(contentsOf: url))
    }

    static let resourceBundleName = "Lodestar_LodestarCore.bundle"

    /// Finds emoji.json without `Bundle.module`, whose accessor traps when the
    /// resource bundle is missing. Looks next to the executable (swift run,
    /// tests) and in the app's Resources folder (scripts/bundle.sh).
    public static func bundledDataURL() -> URL? {
        final class Marker {}
        let fm = FileManager.default
        var dirs: [URL] = []
        if let r = Bundle.main.resourceURL { dirs.append(r) }
        dirs.append(Bundle.main.bundleURL)
        if let exe = Bundle.main.executableURL { dirs.append(exe.deletingLastPathComponent()) }
        let own = Bundle(for: Marker.self).bundleURL
        dirs.append(own.deletingLastPathComponent())
        dirs.append(own)
        for dir in dirs {
            let bundle = dir.appendingPathComponent(resourceBundleName)
            for candidate in [bundle.appendingPathComponent("Contents/Resources/emoji.json"), bundle.appendingPathComponent("emoji.json")]
            where fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

/// Which emoji version the system font can draw, by macOS version.
public enum EmojiAvailability {
    /// Approximate: Apple adds each Unicode emoji release in a point update.
    public static func maxEmojiVersion(macOSMajor major: Int, minor: Int) -> Int {
        switch (major, minor) {
        case (..<13, _): return 130
        case (13, ..<3): return 140
        case (13, _), (14, ..<4): return 150
        case (14, _), (15, ..<4): return 151
        case (15, _), (16...25, _), (26, ..<4): return 160
        default: return 170
        }
    }
}
