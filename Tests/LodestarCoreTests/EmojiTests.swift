import XCTest
@testable import LodestarCore

final class EmojiCatalogTests: XCTestCase {
    static let bundled: EmojiCatalog = {
        do { return try EmojiCatalog.loadBundled() } catch { fatalError("emoji.json didn't load: \(error)") }
    }()

    var catalog: EmojiCatalog { EmojiCatalogTests.bundled }

    func testBundledDataLoads() {
        XCTAssertEqual(catalog.unicodeVersion, "17.0")
        XCTAssertEqual(catalog.categories.map(\.name), [
            "Smileys & People", "Animals & Nature", "Food & Drink", "Activities", "Travel & Places", "Objects", "Symbols", "Flags",
            "Keyboard", "Arrows", "Math", "Currency", "Punctuation & Typography", "Greek Letters", "Stars & Shapes", "Box Drawing",
        ])
        let emoji = catalog.items.filter { catalog.category(of: $0)?.kind == .emoji }
        XCTAssertGreaterThan(emoji.count, 1800, "the full RGI set, minus skin-tone variants")
        XCTAssertGreaterThan(catalog.items.count - emoji.count, 500, "the symbol sections")
        for index in catalog.categories.indices {
            XCTAssertFalse(catalog.items(in: index).isEmpty, "\(catalog.categories[index].name) is empty")
        }
        // Items are grouped by category, in category order.
        XCTAssertEqual(catalog.items.map(\.categoryIndex), catalog.items.map(\.categoryIndex).sorted())
        XCTAssertEqual(catalog.items.first?.glyph, "😀")
    }

    func testNamesKeywordsAndLookup() throws {
        let rocket = try XCTUnwrap(catalog.item(forGlyph: "🚀"))
        XCTAssertEqual(rocket.name, "rocket")
        XCTAssertEqual(rocket.displayName, "Rocket")
        XCTAssertEqual(catalog.item(forGlyph: "😁")?.displayName, "Beaming Face with Smiling Eyes")
        XCTAssertEqual(catalog.item(forGlyph: "😂")?.displayName, "Face with Tears of Joy")
        XCTAssertEqual(EmojiItem.titleCase("flag: the bahamas"), "Flag: The Bahamas")
        XCTAssertEqual(EmojiItem.titleCase("of course"), "Of Course")
        XCTAssertTrue(rocket.keywords.contains("space"))
        XCTAssertEqual(catalog.category(of: rocket)?.name, "Travel & Places")

        let command = try XCTUnwrap(catalog.items.first { $0.glyph == "⌘" })
        XCTAssertEqual(command.displayName, "Command")
        XCTAssertEqual(catalog.category(of: command)?.id, "keyboard")

        // Variation selectors don't matter for lookup.
        XCTAssertEqual(catalog.item(forGlyph: "❤")?.name, "red heart")
        XCTAssertEqual(catalog.item(forGlyph: "❤️")?.name, "red heart")
        XCTAssertEqual(catalog.item(forGlyph: "🇯🇵")?.displayName, "Flag: Japan")
        XCTAssertEqual(EmojiItem.codePoints(of: "👍🏽"), "U+1F44D U+1F3FD")
        XCTAssertEqual(EmojiItem.codePoints(of: "→"), "U+2192")
    }

    func testSymbolsThatHaveEmojiFormsAreForcedToText() throws {
        // ☀ is both a symbol and an emoji; the Stars & Shapes copy asks for text presentation.
        let shapes = try XCTUnwrap(catalog.categories.firstIndex { $0.id == "shapes" })
        let sun = try XCTUnwrap(catalog.items(in: shapes).first { $0.glyph.unicodeScalars.first == "\u{2600}" })
        XCTAssertEqual(sun.glyph.unicodeScalars.last, "\u{FE0E}")
        XCTAssertEqual(sun.version, 0)
    }

    func testAvailabilityFiltersNewerEmoji() {
        let newest = catalog.items.map(\.version).max() ?? 0
        XCTAssertEqual(newest, 170)
        let older = catalog.available(upTo: 140)
        XCTAssertTrue(older.items.allSatisfy { $0.version <= 140 })
        XCTAssertTrue(older.items.allSatisfy { ($0.skinToneVersion ?? 0) <= 140 })
        XCTAssertNil(older.item(forGlyph: "🫨"), "shaking face is Emoji 15.0")
        XCTAssertEqual(older.items.filter { older.category(of: $0)?.kind == .symbol }.count,
                       catalog.items.filter { catalog.category(of: $0)?.kind == .symbol }.count, "symbols are always kept")
        // 💏 exists since Emoji 2.0 but its skin tones arrived in 13.1.
        XCTAssertNotNil(catalog.item(forGlyph: "💏")?.skinToneVersion)
        XCTAssertNil(catalog.available(upTo: 130).item(forGlyph: "💏")?.skinToneVersion)

        XCTAssertEqual(EmojiAvailability.maxEmojiVersion(macOSMajor: 13, minor: 0), 140)
        XCTAssertEqual(EmojiAvailability.maxEmojiVersion(macOSMajor: 14, minor: 4), 151)
        XCTAssertEqual(EmojiAvailability.maxEmojiVersion(macOSMajor: 15, minor: 4), 160)
        XCTAssertEqual(EmojiAvailability.maxEmojiVersion(macOSMajor: 27, minor: 0), 170)
    }
}

final class EmojiSearchTests: XCTestCase {
    var catalog: EmojiCatalog { EmojiCatalogTests.bundled }

    private func top(_ query: String, _ n: Int = 1) -> [String] {
        EmojiSearch.search(query, in: catalog, limit: n).map(\.item.glyph)
    }

    func testNameMatchesRankFirst() {
        XCTAssertEqual(top("rocket"), ["🚀"])
        XCTAssertEqual(top("thumbs up"), ["👍"])
        XCTAssertEqual(top("Red Heart"), ["❤️"])
        XCTAssertTrue(top("cat", 3).contains("🐈"))
        XCTAssertTrue(top("heart", 8).contains("❤️"), "head-noun matches (\"red heart\") land in the first grid row")
        XCTAssertEqual(top("command"), ["⌘"])
        XCTAssertEqual(top("alpha").first.map { $0.lowercased() }, "α")
    }

    func testKeywordsAndPrefixes() {
        XCTAssertTrue(top("launch", 5).contains("🚀"), "CLDR keyword")
        XCTAssertTrue(top("thu", 5).contains("👍"), "prefix of a name word")
        XCTAssertTrue(top("+1", 3).contains("👍"))
        XCTAssertTrue(top("bitcoin", 3).contains("₿"))
        XCTAssertTrue(top("jp", 3).contains("🇯🇵"), "flags are searchable by ISO code")
        XCTAssertTrue(top("cmd", 3).contains("⌘"))
    }

    func testWordStartsOnly() {
        let results = EmojiSearch.search("cat", in: catalog).map(\.item.name)
        XCTAssertFalse(results.contains { $0.contains("vacation") || $0.contains("certificate") })
        XCTAssertTrue(EmojiSearch.search("zzzqqq", in: catalog).isEmpty)
        XCTAssertTrue(EmojiSearch.search("   ", in: catalog).isEmpty)
    }

    func testGlyphAndCodePointQueries() {
        XCTAssertEqual(top("🚀"), ["🚀"])
        XCTAssertEqual(top("U+1F680"), ["🚀"])
        XCTAssertEqual(top("u+2318"), ["⌘"])
    }

    func testStrongMatchesForRootSearch() {
        XCTAssertEqual(EmojiSearch.strongMatches("rocket", in: catalog), ["🚀"].compactMap { catalog.item(forGlyph: $0) })
        XCTAssertFalse(EmojiSearch.strongMatches("heart", in: catalog).isEmpty)
        XCTAssertLessThanOrEqual(EmojiSearch.strongMatches("heart", in: catalog).count, 3)
        XCTAssertTrue(EmojiSearch.strongMatches("roc", in: catalog).isEmpty, "prefixes are not strong")
        XCTAssertTrue(EmojiSearch.strongMatches("ox", in: catalog).isEmpty, "too short")
        XCTAssertTrue(EmojiSearch.strongMatches("2+2", in: catalog).isEmpty, "calculator input")
        XCTAssertTrue(EmojiSearch.strongMatches("command", in: catalog).isEmpty, "plain symbols stay out of root search")
    }
}

final class EmojiSkinToneTests: XCTestCase {
    var catalog: EmojiCatalog { EmojiCatalogTests.bundled }

    func testApplyBuildsValidSequences() throws {
        let bases = catalog.modifierBases
        XCTAssertEqual(EmojiSkinTone.medium.apply(to: "👍", modifierBases: bases), "👍🏽")
        XCTAssertEqual(EmojiSkinTone.none.apply(to: "👍", modifierBases: bases), "👍")
        // The FE0F after the base is dropped.
        XCTAssertEqual(EmojiSkinTone.dark.apply(to: "🖐️", modifierBases: bases), "🖐🏿")
        // ZWJ sequences: tone goes after the person, before the ZWJ.
        XCTAssertEqual(EmojiSkinTone.light.apply(to: "🧑‍💻", modifierBases: bases), "🧑🏻‍💻")
        XCTAssertEqual(EmojiSkinTone.mediumDark.apply(to: "🏃‍♀️", modifierBases: bases), "🏃🏾‍♀️")
        // Both people get the tone; the handshake between them doesn't.
        XCTAssertEqual(EmojiSkinTone.medium.apply(to: "🧑‍🤝‍🧑", modifierBases: bases), "🧑🏽‍🤝‍🧑🏽")
    }

    func testCatalogOnlyTonesEmojiThatSupportIt() throws {
        let rocket = try XCTUnwrap(catalog.item(forGlyph: "🚀"))
        XCTAssertFalse(rocket.supportsSkinTones)
        XCTAssertEqual(catalog.glyph(for: rocket, tone: .dark), "🚀")
        let wave = try XCTUnwrap(catalog.item(forGlyph: "👋"))
        XCTAssertEqual(catalog.glyph(for: wave, tone: .light), "👋🏻")
        XCTAssertGreaterThan(catalog.items.filter(\.supportsSkinTones).count, 300)
    }

    func testConfigValue() {
        XCTAssertEqual(EmojiSkinTone(configValue: nil), EmojiSkinTone.none)
        XCTAssertEqual(EmojiSkinTone(configValue: "medium"), .medium)
        XCTAssertEqual(EmojiSkinTone(configValue: "purple"), EmojiSkinTone.none)
        XCTAssertNil(EmojiSkinTone.none.configValue)
        XCTAssertEqual(EmojiSkinTone.mediumDark.configValue, "mediumDark")
    }

    func testConfigRoundTripKeepsOtherKeys() throws {
        let existing = Data(#"{"hotkey":"cmd+space","custom":1}"#.utf8)
        let (data, config) = try LodestarConfig.updated(existing) { $0.emojiSkinTone = EmojiSkinTone.dark.configValue }
        XCTAssertEqual(config.emojiSkinTone, "dark")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["emojiSkinTone"] as? String, "dark")
        XCTAssertEqual(object["custom"] as? Int, 1)
    }
}

final class EmojiUsageStoreTests: XCTestCase {
    func testRecentsAreMostRecentFirstAndCapped() {
        let store = EmojiUsageStore(url: nil)
        store.recordUse("😀")
        store.recordUse("🚀")
        store.recordUse("😀")
        XCTAssertEqual(store.recents, ["😀", "🚀"])
        for i in 0..<40 { store.recordUse("x\(i)") }
        XCTAssertEqual(store.recents.count, EmojiUsageStore.maxRecents)
        XCTAssertEqual(store.recents.first, "x39")
        store.clearRecents()
        XCTAssertTrue(store.recents.isEmpty)
    }

    func testFavorites() {
        let store = EmojiUsageStore(url: nil)
        store.addFavorite("👍")
        store.addFavorite("🚀")
        store.addFavorite("👍")
        XCTAssertEqual(store.favorites, ["👍", "🚀"])
        XCTAssertTrue(store.isFavorite("🚀"))
        store.moveFavorite("🚀", by: -1)
        XCTAssertEqual(store.favorites, ["🚀", "👍"])
        store.moveFavorite("🚀", by: -1)
        XCTAssertEqual(store.favorites, ["🚀", "👍"])
        store.removeFavorite("🚀")
        XCTAssertEqual(store.favorites, ["👍"])
        XCTAssertFalse(store.isFavorite("🚀"))
    }

    func testPersistence() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lodestar-emoji-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("emoji.json")
        let store = EmojiUsageStore(url: url)
        store.recordUse("🎉")
        store.addFavorite("⌘")
        let reloaded = EmojiUsageStore(url: url)
        XCTAssertEqual(reloaded.state, EmojiUsageStore.State(recents: ["🎉"], favorites: ["⌘"]))
        // A corrupt file starts empty instead of failing.
        try Data("nope".utf8).write(to: url)
        XCTAssertEqual(EmojiUsageStore(url: url).state, EmojiUsageStore.State())
    }
}

final class SectionedGridTests: XCTestCase {
    // Two sections: 10 items (rows of 4: 4, 4, 2) then 3 items.
    let grid = SectionedGrid(sectionSizes: [10, 3], columns: 4)

    func testLeftRightAreLinearAndClamped() {
        XCTAssertEqual(grid.move(from: 0, .left), 0)
        XCTAssertEqual(grid.move(from: 3, .right), 4)
        XCTAssertEqual(grid.move(from: 9, .right), 10, "into the next section")
        XCTAssertEqual(grid.move(from: 12, .right), 12)
    }

    func testDownKeepsColumn() {
        XCTAssertEqual(grid.move(from: 1, .down), 5)
        XCTAssertEqual(grid.move(from: 7, .down), 9, "shorter last row: land on its last item")
        XCTAssertEqual(grid.move(from: 9, .down), 11, "into the next section, same column")
        XCTAssertEqual(grid.move(from: 8, .down), 10)
        XCTAssertEqual(grid.move(from: 11, .down), 11, "last row of the last section stays")
    }

    func testUpKeepsColumn() {
        XCTAssertEqual(grid.move(from: 5, .up), 1)
        XCTAssertEqual(grid.move(from: 2, .up), 2, "first row stays")
        XCTAssertEqual(grid.move(from: 10, .up), 8, "back to the previous section's last row")
        XCTAssertEqual(grid.move(from: 12, .up), 9, "column 2 doesn't exist there: last item")
    }

    func testEmptyAndDegenerate() {
        XCTAssertEqual(SectionedGrid(sectionSizes: [], columns: 8).move(from: 3, .down), 0)
        XCTAssertEqual(SectionedGrid(sectionSizes: [0, 2], columns: 8).sectionSizes, [2])
        XCTAssertEqual(SectionedGrid(sectionSizes: [5], columns: 0).move(from: 0, .down), 1)
    }
}
