import Foundation

/// Word-based search over emoji names and CLDR keywords. Unlike the fuzzy
/// matcher used for apps, every query word must match the start of a word,
/// so "cat" finds 🐈 and 😺 but not "vacation" or "certificate".
public enum EmojiSearch {
    /// Precomputed tokens for one item.
    struct Entry: Sendable {
        let name: String
        let nameTokens: [String]
        let keywords: [String]
        let keywordTokens: [String]
        let bareGlyph: String
        let firstScalar: UInt32

        init(_ item: EmojiItem) {
            name = item.name.lowercased()
            nameTokens = EmojiSearch.tokens(name)
            keywords = item.keywords.map { $0.lowercased() }
            keywordTokens = Array(Set(keywords.flatMap(EmojiSearch.tokens))).sorted()
            bareGlyph = EmojiCatalog.strippingVariationSelectors(item.glyph)
            firstScalar = item.glyph.unicodeScalars.first?.value ?? 0
        }
    }

    public struct Result: Sendable {
        public let item: EmojiItem
        public let score: Double
        /// Every query word equals a word of the name (used for root search).
        public let isStrong: Bool
    }

    /// Splits "flag: Côte d’Ivoire" / "right-pointing arrow" into lowercase
    /// words, keeping hyphenated words whole as well as their parts.
    static func tokens(_ text: String) -> [String] {
        let trim = CharacterSet(charactersIn: ":,.;()[]\"“”‘’'!?")
        var out: [String] = []
        for raw in text.lowercased().split(whereSeparator: { $0 == " " }) {
            let word = raw.trimmingCharacters(in: trim)
            guard !word.isEmpty else { continue }
            out.append(word)
            if word.contains("-") || word.contains("’") {
                out += word.split(whereSeparator: { $0 == "-" || $0 == "’" }).map(String.init).filter { !$0.isEmpty }
            }
        }
        return out
    }

    /// Ranked matches for `query`, best first. Ties keep catalog order.
    public static func search(_ query: String, in catalog: EmojiCatalog, limit: Int = .max) -> [Result] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let words = tokens(q)
        let bareQuery = EmojiCatalog.strippingVariationSelectors(q)
        let codePoint = parseCodePoint(q)

        var results: [(Int, Result)] = []
        for (i, entry) in catalog.index.enumerated() {
            guard let (score, strong) = score(entry, query: q, words: words, bareQuery: bareQuery, codePoint: codePoint) else { continue }
            results.append((i, Result(item: catalog.items[i], score: score, isStrong: strong)))
        }
        results.sort { a, b in a.1.score != b.1.score ? a.1.score > b.1.score : a.0 < b.0 }
        return results.prefix(limit).map(\.1)
    }

    /// A few emoji for the root launcher: only when every query word is a
    /// whole word of the emoji's name ("rocket", "thumbs up"), the query has
    /// at least `minLength` letters, and only emoji, not plain symbols.
    public static func strongMatches(_ query: String, in catalog: EmojiCatalog, limit: Int = 3, minLength: Int = 3) -> [EmojiItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.filter(\.isLetter).count >= minLength, q.allSatisfy({ $0.isLetter || $0 == " " || $0 == "-" }) else { return [] }
        return search(q, in: catalog)
            .filter { $0.isStrong && catalog.category(of: $0.item)?.kind == .emoji }
            .prefix(limit)
            .map(\.item)
    }

    static func parseCodePoint(_ q: String) -> UInt32? {
        var hex = Substring(q)
        if hex.hasPrefix("u+") { hex = hex.dropFirst(2) } else if hex.hasPrefix("0x") { hex = hex.dropFirst(2) } else { return nil }
        guard (2...6).contains(hex.count), let v = UInt32(hex, radix: 16) else { return nil }
        return v
    }

    private static func score(_ e: Entry, query: String, words: [String], bareQuery: String, codePoint: UInt32?) -> (Double, Bool)? {
        // Searching by the character itself, or by code point ("U+1F680").
        if bareQuery == e.bareGlyph { return (1000, false) }
        if let codePoint { return codePoint == e.firstScalar ? (900, false) : nil }
        if query == e.name { return (200, true) }

        var total = 0.0
        var strong = !words.isEmpty
        for (position, word) in words.enumerated() {
            var best = 0.0
            for (i, token) in e.nameTokens.enumerated() {
                let s: Double
                if token == word { s = 10 } else if token.hasPrefix(word) { s = 6 } else { continue }
                // English names end in their head noun ("red heart", "grinning cat"),
                // so a whole-word match on the last word ranks highest, then the first.
                let isLast = i == e.nameTokens.count - 1
                best = max(best, s + (s == 10 && isLast ? 2 : 0) + (i == 0 && position == 0 ? 1 : 0))
            }
            if best < 10 { strong = false }
            if best == 0 {
                for keyword in e.keywords where keyword == word { best = max(best, 7) }
                if best == 0 { for token in e.keywordTokens where token.hasPrefix(word) { best = max(best, token == word ? 5 : 3) } }
            }
            if best == 0 { return nil }
            total += best
        }
        if e.name.hasPrefix(query) { total += 1 }
        // Prefer short names: "cat" before "cat with tears of joy".
        total -= Double(e.nameTokens.count) * 0.3
        return (total, strong)
    }
}
