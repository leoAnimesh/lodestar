import XCTest
@testable import LodestarCore

final class ClipboardClassifierTests: XCTestCase {
    func testLinks() {
        XCTAssertEqual(ClipboardClassifier.link(in: "https://github.com/leoAnimesh/lodestar")?.host, "github.com")
        XCTAssertEqual(ClipboardClassifier.link(in: "  http://example.com/a?b=c  \n")?.absoluteString, "http://example.com/a?b=c")
        XCTAssertEqual(ClipboardClassifier.link(in: "www.apple.com")?.absoluteString, "https://www.apple.com")
        XCTAssertNotNil(ClipboardClassifier.link(in: "http://localhost:8080/x"))
        XCTAssertNotNil(ClipboardClassifier.link(in: "mailto:someone@example.com"))
        for text in ["", "github.com", "see https://github.com", "https://github.com and more", "https://", "ftp:/x",
                     "javascript:alert(1)", "file:///etc/hosts", "mailto:", "https://nodot"] {
            XCTAssertNil(ClipboardClassifier.link(in: text), text)
        }
    }

    func testColors() {
        XCTAssertEqual(ClipboardClassifier.color(in: "#0C0D0E"), SRGBColor(red: 12, green: 13, blue: 14))
        XCTAssertEqual(ClipboardClassifier.color(in: " #fff\n"), SRGBColor(red: 255, green: 255, blue: 255))
        XCTAssertEqual(ClipboardClassifier.color(in: "#3A7BFF80"), SRGBColor(red: 58, green: 123, blue: 255))
        XCTAssertEqual(ClipboardClassifier.color(in: "#38F8"), SRGBColor(red: 0x33, green: 0x88, blue: 0xFF))
        XCTAssertEqual(ClipboardClassifier.color(in: "rgb(58, 123, 255)"), SRGBColor(red: 58, green: 123, blue: 255))
        XCTAssertEqual(ClipboardClassifier.color(in: "RGBA(58,123,255,0.5)"), SRGBColor(red: 58, green: 123, blue: 255))
        XCTAssertEqual(ClipboardClassifier.color(in: "rgb(58 123 255 / 50%)"), SRGBColor(red: 58, green: 123, blue: 255))
        XCTAssertEqual(ClipboardClassifier.color(in: "rgb(100%, 0%, 50%)"), SRGBColor(red: 255, green: 0, blue: 128))
        XCTAssertEqual(ClipboardClassifier.color(in: "hsl(220, 100%, 61%)")?.hex, "#387AFF")
        XCTAssertEqual(ClipboardClassifier.color(in: "hsl(0deg 100% 50%)"), SRGBColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(ClipboardClassifier.color(in: "hsla(120, 100%, 25%, 1)"), SRGBColor(red: 0, green: 128, blue: 0))
        for text in ["123456", "#12345", "#GGGGGG", "rgb(300, 0, 0)", "rgb(1, 2)", "rgb(1,2,3", "hsl(10, 50, 50)",
                     "rgba(1,2,3,2)", "#0C0D0E is my color", "color: #fff"] {
            XCTAssertNil(ClipboardClassifier.color(in: text), text)
        }
    }

    func testKind() {
        XCTAssertEqual(ClipboardClassifier.kind(of: "#0C0D0E"), .color)
        XCTAssertEqual(ClipboardClassifier.kind(of: "https://github.com"), .link)
        XCTAssertEqual(ClipboardClassifier.kind(of: "hello world"), .text)
        XCTAssertEqual(ClipboardEntry.text("rgb(1, 2, 3)", date: Date()).kind, .color)
    }

    func testTextStats() {
        let stats = ClipboardTextStats("Hello, world!\nSecond line here\n")
        XCTAssertEqual(stats.characters, 31)
        XCTAssertEqual(stats.words, 5)
        XCTAssertEqual(stats.lines, 2)
        XCTAssertEqual(ClipboardTextStats("").lines, 0)
        XCTAssertEqual(ClipboardTextStats("one").lines, 1)
        XCTAssertEqual(ClipboardTextStats("é👍🏽").characters, 2, "counts grapheme clusters")
    }
}

final class ClipboardEntryTests: XCTestCase {
    let date = Date(timeIntervalSince1970: 1_700_000_000)

    func image(_ digest: String, file: String = "a.png") -> ClipboardImageInfo {
        ClipboardImageInfo(fileName: file, thumbnailFileName: file.replacingOccurrences(of: ".png", with: "-thumb.png"),
                           width: 1404, height: 538, byteSize: 120_000, digest: digest)
    }

    func testTitles() {
        XCTAssertEqual(ClipboardEntry(kind: .image, text: nil, date: date, image: image("x")).title, "Image (1404×538)")
        XCTAssertEqual(ClipboardEntry(kind: .file, text: "/Users/me/Report.pdf", date: date).title, "Report.pdf")
        XCTAssertEqual(ClipboardEntry(kind: .file, text: "/a/one.txt\n/a/two.txt\n/a/three.txt", date: date).title, "one.txt and 2 more")
        XCTAssertEqual(ClipboardEntry.text("  first line\n\n  second  \n", date: date).title, "first line second")
        XCTAssertEqual(ClipboardEntry.text(String(repeating: "x", count: 500), date: date).title.count, 200)
    }

    func testFilePathsAndSearchText() {
        let entry = ClipboardEntry(kind: .file, text: "/a/one.txt\n/b/two.txt", date: date)
        XCTAssertEqual(entry.filePaths, ["/a/one.txt", "/b/two.txt"])
        XCTAssertTrue(entry.searchText.contains("two.txt"))
        XCTAssertEqual(ClipboardEntry.text("x", date: date).filePaths, [])
    }

    func testOwnedFiles() {
        var entry = ClipboardEntry(kind: .image, text: nil, date: date, image: image("x"))
        XCTAssertEqual(entry.ownedFileNames, ["a.png", "a-thumb.png"])
        entry = ClipboardEntry(kind: .text, text: "hi", date: date, richText: ClipboardRichText(format: .rtf, fileName: "r.rtf"))
        XCTAssertEqual(entry.ownedFileNames, ["r.rtf"])
    }
}

final class ClipboardArchiveTests: XCTestCase {
    func testMigratesTextOnlyFormat() throws {
        // What version 1 wrote: JSONEncoder's default date encoding (seconds
        // since the reference date) and only text/date/sourceApp.
        let legacy = """
        [{"text":"hello","date":720000000,"sourceApp":"Notes"},
         {"text":"https://github.com","date":719999000.625},
         {"text":"#0C0D0E","date":719998000,"sourceApp":null}]
        """
        let decoded = try ClipboardArchive.decode(Data(legacy.utf8))
        XCTAssertTrue(decoded.needsResave)
        XCTAssertEqual(decoded.entries.map(\.kind), [.text, .link, .color])
        XCTAssertEqual(decoded.entries.map(\.text), ["hello", "https://github.com", "#0C0D0E"])
        XCTAssertEqual(decoded.entries[0].sourceApp, "Notes")
        XCTAssertEqual(decoded.entries[0].date, Date(timeIntervalSinceReferenceDate: 720_000_000))
        XCTAssertFalse(decoded.entries[0].pinned)
        XCTAssertEqual(Set(decoded.entries.map(\.id)).count, 3)

        // Saved again, the file is in the current format and round-trips.
        let reencoded = try ClipboardArchive.decode(ClipboardArchive.encode(decoded.entries))
        XCTAssertFalse(reencoded.needsResave)
        XCTAssertEqual(reencoded.entries, decoded.entries)
    }

    func testRoundTripsEveryKind() throws {
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let entries = [
            ClipboardEntry(kind: .image, text: nil, date: date, sourceApp: "Preview", sourceBundleID: "com.apple.Preview", pinned: true,
                           image: ClipboardImageInfo(fileName: "i.png", thumbnailFileName: "i-thumb.png", width: 10, height: 20, byteSize: 300, digest: "abc")),
            ClipboardEntry(kind: .file, text: "/etc/hosts", date: date),
            ClipboardEntry(kind: .text, text: "rich", date: date, richText: ClipboardRichText(format: .html, fileName: "r.html")),
        ]
        let decoded = try ClipboardArchive.decode(ClipboardArchive.encode(entries))
        XCTAssertEqual(decoded.entries, entries)
        XCTAssertFalse(decoded.needsResave)
    }

    func testSkipsBadEntriesAndRejectsNonArrays() throws {
        let mixed = """
        [{"text":"ok","date":1}, {"date":2}, 42, {"kind":"image","text":null,"date":3}, {"kind":"bogus","text":"https://a.com","date":4}]
        """
        let decoded = try ClipboardArchive.decode(Data(mixed.utf8))
        XCTAssertEqual(decoded.entries.map(\.text), ["ok", "https://a.com"])
        XCTAssertEqual(decoded.entries.last?.kind, .link, "an unknown kind is detected again from the text")
        XCTAssertTrue(decoded.needsResave)
        XCTAssertThrowsError(try ClipboardArchive.decode(Data("{\"text\":\"x\"}".utf8)))
        XCTAssertThrowsError(try ClipboardArchive.decode(Data("not json".utf8)))
        XCTAssertEqual(try ClipboardArchive.decode(Data("[]".utf8)).entries, [])
    }

    func testOrphanedFiles() {
        let entry = ClipboardEntry(kind: .image, text: nil, date: Date(),
                                   image: ClipboardImageInfo(fileName: "a.png", thumbnailFileName: "a-t.png", width: 1, height: 1, byteSize: 1, digest: "d"))
        XCTAssertEqual(ClipboardArchive.orphanedFiles(["a.png", "a-t.png", "b.png", ".DS_Store"], entries: [entry]), ["b.png"])
    }
}

final class ClipboardHistoryLogicTests: XCTestCase {
    let now = Date(timeIntervalSinceReferenceDate: 750_000_000)

    func text(_ s: String, _ minutesAgo: Double = 0, pinned: Bool = false) -> ClipboardEntry {
        var e = ClipboardEntry.text(s, date: now.addingTimeInterval(-minutesAgo * 60))
        e.pinned = pinned
        return e
    }

    func imageEntry(_ digest: String, file: String) -> ClipboardEntry {
        ClipboardEntry(kind: .image, text: nil, date: now,
                       image: ClipboardImageInfo(fileName: file, thumbnailFileName: nil, width: 1, height: 1, byteSize: 1, digest: digest))
    }

    func testInsertDedupesKeepingIDAndPin() {
        let old = text("a", 10, pinned: true)
        let other = text("b", 5)
        let change = ClipboardHistoryLogic.insert(text("a"), into: [other, old], limit: 10)
        XCTAssertEqual(change.entries.map(\.text), ["a", "b"])
        XCTAssertEqual(change.entries[0].id, old.id)
        XCTAssertTrue(change.entries[0].pinned)
        XCTAssertEqual(change.entries[0].date, now)
        XCTAssertEqual(change.removedFiles, [])
    }

    func testImageDedupeByDigestRemovesOldFiles() {
        let old = imageEntry("same", file: "old.png")
        let change = ClipboardHistoryLogic.insert(imageEntry("same", file: "new.png"), into: [old], limit: 10)
        XCTAssertEqual(change.entries.count, 1)
        XCTAssertEqual(change.entries[0].image?.fileName, "new.png")
        XCTAssertEqual(change.removedFiles, ["old.png"])
        // A different image is a new entry; text never matches an image.
        XCTAssertEqual(ClipboardHistoryLogic.insert(imageEntry("other", file: "x.png"), into: [old], limit: 10).entries.count, 2)
        XCTAssertFalse(text("a").hasSameContent(as: old))
    }

    func testPruneDropsOldestUnpinnedAndReportsFiles() {
        let entries = [text("1"), imageEntry("i", file: "i.png"), text("3", pinned: true), text("4")]
        let change = ClipboardHistoryLogic.prune(entries, limit: 2)
        XCTAssertEqual(change.entries.map(\.text), ["1", "3"])
        XCTAssertEqual(change.removedFiles, ["i.png"])
        // Pins survive even past the limit.
        let pinned = [text("a", pinned: true), text("b", pinned: true), text("c")]
        XCTAssertEqual(ClipboardHistoryLogic.prune(pinned, limit: 1).entries.map(\.text), ["a", "b"])
        XCTAssertEqual(ClipboardHistoryLogic.prune(pinned, limit: 5).entries.count, 3)
    }

    func testInsertPrunes() {
        let change = ClipboardHistoryLogic.insert(text("new"), into: [text("a"), imageEntry("i", file: "i.png")], limit: 2)
        XCTAssertEqual(change.entries.map(\.text), ["new", "a"])
        XCTAssertEqual(change.removedFiles, ["i.png"])
    }

    func testRemoveClearPinPromote() {
        let a = text("a"), b = imageEntry("i", file: "i.png"), c = text("c", 30)
        let removed = ClipboardHistoryLogic.remove(b.id, from: [a, b, c])
        XCTAssertEqual(removed.entries.map(\.id), [a.id, c.id])
        XCTAssertEqual(removed.removedFiles, ["i.png"])
        XCTAssertEqual(ClipboardHistoryLogic.clear([a, b, c]).removedFiles, ["i.png"])
        XCTAssertEqual(ClipboardHistoryLogic.clear([a, b, c]).entries, [])
        XCTAssertTrue(ClipboardHistoryLogic.setPinned(true, id: c.id, in: [a, c])[1].pinned)
        let promoted = ClipboardHistoryLogic.promote(c.id, in: [a, b, c], date: now)
        XCTAssertEqual(promoted.map(\.id), [c.id, a.id, b.id])
        XCTAssertEqual(promoted[0].date, now)
    }
}

final class ClipboardGroupingTests: XCTestCase {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)!
    }

    func testSections() {
        let now = date("2026-10-25T09:00:00Z")
        XCTAssertEqual(ClipboardSection.forDate(date("2026-10-25T00:00:01Z"), now: now, calendar: calendar), .today)
        XCTAssertEqual(ClipboardSection.forDate(date("2026-10-25T23:00:00Z"), now: now, calendar: calendar), .today)
        XCTAssertEqual(ClipboardSection.forDate(date("2026-10-24T23:59:59Z"), now: now, calendar: calendar), .yesterday)
        XCTAssertEqual(ClipboardSection.forDate(date("2026-10-24T00:00:00Z"), now: now, calendar: calendar), .yesterday)
        XCTAssertEqual(ClipboardSection.forDate(date("2026-10-20T12:00:00Z"), now: now, calendar: calendar), .thisWeek)
        XCTAssertEqual(ClipboardSection.forDate(date("2026-10-18T00:00:00Z"), now: now, calendar: calendar), .thisWeek)
        XCTAssertEqual(ClipboardSection.forDate(date("2026-10-17T23:59:59Z"), now: now, calendar: calendar), .older)
    }

    func testGroupPutsPinnedFirstAndKeepsOrder() {
        let now = date("2026-10-25T09:00:00Z")
        func entry(_ t: String, _ d: String, pinned: Bool = false) -> ClipboardEntry {
            var e = ClipboardEntry.text(t, date: date(d)); e.pinned = pinned; return e
        }
        let entries = [entry("t1", "2026-10-25T08:00:00Z"), entry("old", "2026-01-01T00:00:00Z", pinned: true),
                       entry("t2", "2026-10-25T07:00:00Z"), entry("y", "2026-10-24T07:00:00Z"), entry("o", "2025-01-01T00:00:00Z")]
        let groups = ClipboardSection.group(entries, now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.section), [.pinned, .today, .yesterday, .older])
        XCTAssertEqual(groups.map { $0.entries.compactMap(\.text) }, [["old"], ["t1", "t2"], ["y"], ["o"]])
        XCTAssertEqual(groups.map(\.section.title), ["Pinned", "Today", "Yesterday", "Older"])
    }

    func testTypeFilterAndSearch() {
        let d = Date()
        let entries = [ClipboardEntry.text("Hello World", date: d), ClipboardEntry.text("https://github.com/x", date: d),
                       ClipboardEntry.text("#0C0D0E", date: d), ClipboardEntry(kind: .file, text: "/Users/me/Notes.md", date: d),
                       ClipboardEntry(kind: .image, text: nil, date: d, sourceApp: "Preview",
                                      image: ClipboardImageInfo(fileName: "i", thumbnailFileName: nil, width: 4, height: 3, byteSize: 9, digest: "d"))]
        XCTAssertEqual(ClipboardTypeFilter.filter(entries, type: .all, query: "").count, 5)
        XCTAssertEqual(ClipboardTypeFilter.filter(entries, type: .text, query: "").map(\.kind), [.text])
        XCTAssertEqual(ClipboardTypeFilter.filter(entries, type: .links, query: "").map(\.kind), [.link])
        XCTAssertEqual(ClipboardTypeFilter.filter(entries, type: .colors, query: "").map(\.kind), [.color])
        XCTAssertEqual(ClipboardTypeFilter.filter(entries, type: .images, query: "").map(\.kind), [.image])
        XCTAssertEqual(ClipboardTypeFilter.filter(entries, type: .files, query: "").map(\.kind), [.file])
        XCTAssertEqual(ClipboardTypeFilter.filter(entries, type: .all, query: "world hello").map(\.kind), [.text])
        XCTAssertEqual(ClipboardTypeFilter.filter(entries, type: .all, query: "notes").map(\.kind), [.file])
        XCTAssertEqual(ClipboardTypeFilter.filter(entries, type: .all, query: "preview").map(\.kind), [.image])
        XCTAssertEqual(ClipboardTypeFilter.filter(entries, type: .text, query: "github"), [])
        XCTAssertEqual(ClipboardTypeFilter.allCases.map(\.title), ["All Types", "Text", "Images", "Links", "Colors", "Files"])
    }
}
