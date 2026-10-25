import XCTest
@testable import LodestarCore

final class ListSelectionTests: XCTestCase {
    func testSelectByIndexClampsAndRecordsID() {
        var s = ListSelection()
        s.select(index: 2, in: ["a", "b", "c"])
        XCTAssertEqual(s.id, "c"); XCTAssertEqual(s.index, 2)
        s.select(index: 9, in: ["a", "b"])
        XCTAssertEqual(s.id, "b"); XCTAssertEqual(s.index, 1)
        s.select(index: -1, in: ["a", "b"])
        XCTAssertEqual(s.id, "a"); XCTAssertEqual(s.index, 0)
        s.select(index: 0, in: [])
        XCTAssertNil(s.id); XCTAssertEqual(s.index, 0)
    }

    /// The clipboard bug: a background refresh must not move the selection
    /// back to the first row.
    func testRefreshKeepsSelectedItemByID() {
        var s = ListSelection()
        let ids = ["pinned", "text", "image", "color"]
        s.select(index: 2, in: ids)
        s.update(to: ids)
        XCTAssertEqual(s.id, "image"); XCTAssertEqual(s.index, 2)
        // A new copy arrives on top: the image moves down, still selected.
        s.update(to: ["pinned", "new", "text", "image", "color"])
        XCTAssertEqual(s.id, "image"); XCTAssertEqual(s.index, 3)
        // Filtered down: still the image.
        s.update(to: ["image"])
        XCTAssertEqual(s.id, "image"); XCTAssertEqual(s.index, 0)
    }

    func testRemovedItemSelectsNeighbourNotTop() {
        var s = ListSelection()
        s.select(index: 2, in: ["a", "b", "c", "d"])
        s.update(to: ["a", "b", "d"])
        XCTAssertEqual(s.id, "d"); XCTAssertEqual(s.index, 2)
        s.update(to: ["a", "b"])
        XCTAssertEqual(s.id, "b"); XCTAssertEqual(s.index, 1)
        s.update(to: [])
        XCTAssertNil(s.id)
        s.update(to: ["x"])
        XCTAssertEqual(s.id, "x")
    }

    func testResetAndSelectByID() {
        var s = ListSelection()
        s.select(index: 1, in: ["a", "b"])
        s.reset(in: ["q", "r"])
        XCTAssertEqual(s.id, "q"); XCTAssertEqual(s.index, 0)
        XCTAssertTrue(s.select(id: "r", in: ["q", "r"]))
        XCTAssertEqual(s.index, 1)
        XCTAssertFalse(s.select(id: "zz", in: ["q", "r"]))
        XCTAssertEqual(s.id, "r"); XCTAssertEqual(s.index, 1)
    }
}

final class OpenWithAppsTests: XCTestCase {
    private func app(_ name: String, _ path: String, _ id: String?) -> OpenWithApps.Candidate {
        .init(name: name, path: path, bundleID: id)
    }

    func testDefaultFirstThenByNameWithoutDuplicates() {
        let candidates = [
            app("TextEdit", "/System/Applications/TextEdit.app", "com.apple.TextEdit"),
            app("Xcode", "/Applications/Xcode.app", "com.apple.dt.Xcode"),
            app("BBEdit", "/Applications/BBEdit.app", "com.barebones.bbedit"),
            app("Xcode", "/Users/me/Downloads/Xcode.app", "com.apple.dt.Xcode"),
            app("BBEdit", "/Applications/BBEdit.app/", "com.barebones.bbedit"),
        ]
        let ordered = OpenWithApps.order(candidates, defaultPath: "/Applications/Xcode.app/")
        XCTAssertEqual(ordered.map(\.app.name), ["Xcode", "BBEdit", "TextEdit"])
        XCTAssertEqual(ordered.map(\.isDefault), [true, false, false])
        XCTAssertEqual(ordered[0].app.path, "/Applications/Xcode.app")
    }

    func testNoDefault() {
        let ordered = OpenWithApps.order([app("b", "/Applications/b.app", nil), app("A", "/Applications/A.app", nil)],
                                         defaultPath: nil)
        XCTAssertEqual(ordered.map(\.app.name), ["A", "b"])
        XCTAssertFalse(ordered.contains { $0.isDefault })
        XCTAssertTrue(OpenWithApps.order([], defaultPath: "/x.app").isEmpty)
    }
}
