import Foundation

/// Recently used and favorite emoji, persisted as JSON (by default
/// ~/Library/Application Support/Lodestar/emoji.json). Entries are default
/// (untoned) glyphs, so changing the skin tone applies to them too.
public final class EmojiUsageStore {
    public struct State: Codable, Equatable, Sendable {
        public var recents: [String] = []
        public var favorites: [String] = []
        public init(recents: [String] = [], favorites: [String] = []) {
            self.recents = recents
            self.favorites = favorites
        }
    }

    public static let maxRecents = 16
    public static let maxFavorites = 64

    public private(set) var state: State
    private let url: URL?

    /// - Parameter url: file to persist to; nil keeps it in memory only.
    public init(url: URL?) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(State.self, from: data) {
            state = decoded
        } else {
            state = State()
        }
    }

    public var recents: [String] { state.recents }
    public var favorites: [String] { state.favorites }

    /// Moves `glyph` to the front of the recents.
    public func recordUse(_ glyph: String) {
        state.recents.removeAll { $0 == glyph }
        state.recents.insert(glyph, at: 0)
        if state.recents.count > EmojiUsageStore.maxRecents { state.recents.removeLast(state.recents.count - EmojiUsageStore.maxRecents) }
        save()
    }

    public func clearRecents() {
        state.recents.removeAll()
        save()
    }

    public func isFavorite(_ glyph: String) -> Bool { state.favorites.contains(glyph) }

    /// Adds to the end of the favorites. Returns false if the list is full.
    @discardableResult
    public func addFavorite(_ glyph: String) -> Bool {
        guard !isFavorite(glyph) else { return true }
        guard state.favorites.count < EmojiUsageStore.maxFavorites else { return false }
        state.favorites.append(glyph)
        save()
        return true
    }

    public func removeFavorite(_ glyph: String) {
        state.favorites.removeAll { $0 == glyph }
        save()
    }

    /// Moves a favorite one place earlier (`offset` -1) or later (+1).
    public func moveFavorite(_ glyph: String, by offset: Int) {
        guard let i = state.favorites.firstIndex(of: glyph) else { return }
        let j = min(max(i + offset, 0), state.favorites.count - 1)
        guard i != j else { return }
        state.favorites.remove(at: i)
        state.favorites.insert(glyph, at: j)
        save()
    }

    private func save() {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: url, options: .atomic)
        } catch {
            // Non-fatal: recents and favorites just won't persist.
        }
    }
}

/// Arrow-key movement in a grid split into sections, where each section
/// starts on a new row (like the emoji picker's category headers).
public struct SectionedGrid: Equatable, Sendable {
    public enum Direction: Sendable { case left, right, up, down }

    public let sectionSizes: [Int]
    public let columns: Int

    public init(sectionSizes: [Int], columns: Int) {
        self.sectionSizes = sectionSizes.filter { $0 > 0 }
        self.columns = max(columns, 1)
    }

    public var count: Int { sectionSizes.reduce(0, +) }

    /// The flat index reached by moving from `index`. Left/right step through
    /// the flat order; up/down keep the column, landing on the last item of a
    /// shorter row, and cross into the neighboring section.
    public func move(from index: Int, _ direction: Direction) -> Int {
        guard count > 0 else { return 0 }
        let index = min(max(index, 0), count - 1)
        switch direction {
        case .left: return max(index - 1, 0)
        case .right: return min(index + 1, count - 1)
        case .up, .down: break
        }
        var start = 0, section = 0
        while index >= start + sectionSizes[section] { start += sectionSizes[section]; section += 1 }
        let position = index - start
        let row = position / columns, column = position % columns
        let size = sectionSizes[section]

        if direction == .down {
            if (row + 1) * columns < size { return start + min((row + 1) * columns + column, size - 1) }
            guard section + 1 < sectionSizes.count else { return index }
            return start + size + min(column, sectionSizes[section + 1] - 1)
        } else {
            if row > 0 { return start + (row - 1) * columns + column }
            guard section > 0 else { return index }
            let previous = sectionSizes[section - 1]
            let lastRow = (previous - 1) / columns
            return start - previous + min(lastRow * columns + column, previous - 1)
        }
    }
}
