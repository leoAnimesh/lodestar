import AppKit
import LodestarCore

/// Shared state for "Search Emoji & Symbols": the bundled catalog (filtered
/// to what this macOS can draw), recents/favorites and the default skin tone.
/// Used by the grid screen and by the inline results in root search.
final class EmojiLibrary {
    let usage: EmojiUsageStore
    var skinTone: EmojiSkinTone = .none
    /// Saves a new default skin tone to config.json and applies it.
    var onChangeSkinTone: ((EmojiSkinTone) -> Void)?

    private var loaded: EmojiCatalog?
    private var loadFailed = false

    init(usageURL: URL) {
        usage = EmojiUsageStore(url: usageURL)
    }

    /// Decodes the catalog off the main thread so the first search is instant.
    func preload() {
        DispatchQueue.global(qos: .utility).async {
            let catalog = EmojiLibrary.load()
            DispatchQueue.main.async {
                if self.loaded == nil { self.loaded = catalog }
                if catalog == nil { self.loadFailed = true }
            }
        }
    }

    /// nil only if emoji.json is missing from the build.
    var catalog: EmojiCatalog? {
        if loaded == nil && !loadFailed {
            loaded = EmojiLibrary.load()
            loadFailed = loaded == nil
        }
        return loaded
    }

    private static func load() -> EmojiCatalog? {
        do {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            return try EmojiCatalog.loadBundled()
                .available(upTo: EmojiAvailability.maxEmojiVersion(macOSMajor: os.majorVersion, minor: os.minorVersion))
        } catch {
            NSLog("Lodestar: could not load emoji data: \(error)")
            return nil
        }
    }

    func glyph(for item: EmojiItem) -> String {
        catalog?.glyph(for: item, tone: skinTone) ?? item.glyph
    }

    // MARK: Items

    /// A launcher item for `emoji`. `idPrefix` keeps IDs unique when the same
    /// emoji appears in several sections (Favorites, Recently Used, its category).
    func launcherItem(_ emoji: EmojiItem, idPrefix: String, section: String?, refresh: @escaping () -> Void) -> LauncherItem {
        let base = emoji.glyph
        let category = catalog?.category(of: emoji)
        let favorite = usage.isFavorite(base)
        let name = emoji.displayName
        var actions: [LauncherAction] = [
            LauncherAction("Paste \(category?.kind == .symbol ? "Symbol" : "Emoji")", symbol: "doc.on.clipboard") { [weak self] in
                guard let self else { return .stay }
                let text = self.glyph(for: emoji)
                self.usage.recordUse(base)
                if SystemActions.ensureAccessibility(prompt: false) {
                    return .closeThen { SystemActions.paste(text) }
                }
                // Without Accessibility we can't send ⌘V: copy and say so.
                SystemActions.copy(text)
                return .toast("Copied \(text) — allow Accessibility to paste directly")
            },
            LauncherAction("Copy to Clipboard", symbol: "doc.on.doc") { [weak self] in
                guard let self else { return .stay }
                let text = self.glyph(for: emoji)
                self.usage.recordUse(base)
                SystemActions.copy(text)
                return .close
            },
            LauncherAction("Copy Name", symbol: "textformat") {
                SystemActions.copy(name)
                return .toast("Copied “\(name)”")
            },
            LauncherAction("Copy Unicode Code Point", symbol: "number") { [weak self] in
                let points = EmojiItem.codePoints(of: self?.glyph(for: emoji) ?? base)
                SystemActions.copy(points)
                return .toast("Copied \(points)")
            },
            LauncherAction(favorite ? "Remove from Favorites" : "Add to Favorites", symbol: favorite ? "star.slash" : "star") { [weak self] in
                guard let self else { return .stay }
                if favorite {
                    self.usage.removeFavorite(base)
                    refresh()
                    return .toast("Removed from Favorites")
                }
                guard self.usage.addFavorite(base) else { return .toast("Favorites are full (\(EmojiUsageStore.maxFavorites))") }
                refresh()
                return .toast("Added to Favorites")
            },
        ]
        if favorite && idPrefix == "fav" {
            actions.append(LauncherAction("Move Earlier in Favorites", symbol: "arrow.left") { [weak self] in
                self?.usage.moveFavorite(base, by: -1); refresh(); return .stay
            })
            actions.append(LauncherAction("Move Later in Favorites", symbol: "arrow.right") { [weak self] in
                self?.usage.moveFavorite(base, by: 1); refresh(); return .stay
            })
        }
        if emoji.supportsSkinTones {
            actions.append(LauncherAction("Change Default Skin Tone…", symbol: "hand.raised") { [weak self] in
                guard let self else { return .stay }
                return .push(SkinToneScreen(library: self, sample: emoji))
            })
        }
        if idPrefix == "recent" {
            actions.append(LauncherAction("Clear Recently Used", symbol: "clock.arrow.circlepath") { [weak self] in
                self?.usage.clearRecents(); refresh(); return .toast("Cleared recently used")
            })
        }
        return LauncherItem(
            id: "\(idPrefix):\(base)",
            title: name,
            subtitle: category?.name,
            icon: .text(glyph(for: emoji)),
            accessory: category?.kind == .symbol ? "Symbol" : "Emoji",
            actions: actions,
            tracksUsage: false,
            section: section
        )
    }
}

/// The emoji & symbols grid.
final class EmojiScreen: ListScreen {
    let title = "Emoji & Symbols"
    let placeholder = "Search emoji and symbols…"
    let presentation = ScreenPresentation.grid(columns: EmojiScreen.columns)
    weak var host: ScreenHost?
    static let columns = 8

    private let library: EmojiLibrary
    private var lastQuery = ""

    init(library: EmojiLibrary) { self.library = library }

    func search(_ query: String) -> [LauncherItem] {
        lastQuery = query
        guard let catalog = library.catalog else {
            host?.showToast("Emoji data is missing from this build")
            return []
        }
        let refresh: () -> Void = { [weak self] in
            guard let self else { return }
            self.host?.setItems(self.search(self.lastQuery), for: self)
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var rows: [LauncherItem] = []

        if trimmed.isEmpty {
            let favorites = library.usage.favorites.compactMap(catalog.item(forGlyph:))
            rows += favorites.map { library.launcherItem($0, idPrefix: "fav", section: "Favorites", refresh: refresh) }
            let recents = library.usage.recents.compactMap(catalog.item(forGlyph:))
            rows += recents.map { library.launcherItem($0, idPrefix: "recent", section: "Recently Used", refresh: refresh) }
            for (index, category) in catalog.categories.enumerated() {
                rows += catalog.items(in: index).map {
                    library.launcherItem($0, idPrefix: category.id, section: category.name, refresh: refresh)
                }
            }
            return rows
        }

        // Search: best matches first, emoji before plain symbols.
        let results = EmojiSearch.search(trimmed, in: catalog)
        for kind in [EmojiCategory.Kind.emoji, .symbol] {
            let matching = results.filter { catalog.category(of: $0.item)?.kind == kind }
            rows += matching.map {
                library.launcherItem($0.item, idPrefix: "result", section: kind == .emoji ? "Emoji" : "Symbols", refresh: refresh)
            }
        }
        return rows
    }
}

/// Picks the default skin tone, previewing it on the selected emoji.
final class SkinToneScreen: ListScreen {
    let title = "Default Skin Tone"
    let placeholder = "Choose a default skin tone…"
    weak var host: ScreenHost?
    private let library: EmojiLibrary
    private let sample: EmojiItem

    init(library: EmojiLibrary, sample: EmojiItem) {
        self.library = library
        self.sample = sample
    }

    func search(_ query: String) -> [LauncherItem] {
        guard let catalog = library.catalog else { return [] }
        let rows = EmojiSkinTone.allCases.map { tone -> LauncherItem in
            LauncherItem(
                id: "tone:\(tone.rawValue)",
                title: tone.title,
                subtitle: nil,
                icon: .text(catalog.glyph(for: sample, tone: tone)),
                accessory: tone == library.skinTone ? "Current" : nil,
                actions: [LauncherAction("Use \(tone.title)", symbol: "checkmark") { [weak self] in
                    guard let self else { return .stay }
                    self.library.onChangeSkinTone?(tone)
                    self.library.skinTone = tone
                    if let host = self.host as? LauncherViewModel { host.pop() }
                    return .toast("Skin tone: \(tone.title)")
                }],
                tracksUsage: false
            )
        }
        guard !query.isEmpty else { return rows }
        return rows.filter { FuzzyMatcher.match(query, in: $0.title) != nil }
    }
}
