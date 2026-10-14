import XCTest
@testable import LodestarCore

final class AppDedupeTests: XCTestCase {
    private func app(_ name: String, _ path: String, resolved: String? = nil, id: String? = nil,
                     v: String? = nil, hidden: Bool = false) -> AppCandidate {
        AppCandidate(name: name, path: path, resolvedPath: resolved ?? path, bundleID: id, version: v, isSystemHidden: hidden)
    }

    func testSameBundleIDKeepsOne() {
        let r = AppDedupe.dedupe([
            app("Foo", "/System/Applications/Foo.app", id: "com.x.foo", v: "1.0"),
            app("Foo", "/Applications/Foo.app", id: "com.x.foo", v: "1.0"),
        ])
        XCTAssertEqual(r.map(\.path), ["/Applications/Foo.app"])
    }

    func testBundleIDIsCaseInsensitive() {
        let r = AppDedupe.dedupe([app("A", "/Applications/A.app", id: "com.X.a"), app("A", "/Applications/B.app", id: "com.x.A")])
        XCTAssertEqual(r.count, 1)
    }

    func testNewerVersionWins() {
        let r = AppDedupe.dedupe([
            app("Foo", "/Applications/Foo.app", id: "com.x.foo", v: "1.9"),
            app("Foo", "/Users/me/Applications/Foo.app", id: "com.x.foo", v: "1.10"),
        ])
        XCTAssertEqual(r.map(\.path), ["/Users/me/Applications/Foo.app"])
    }

    func testRealBeatsAlias() {
        let alias = app("Foo", "/Applications/Utilities/Foo.app", resolved: "/Applications/Foo.app", id: "com.x.foo", v: "1")
        let real = app("Foo", "/Applications/Foo.app", id: "com.x.foo", v: "1")
        XCTAssertTrue(alias.isAlias)
        XCTAssertFalse(real.isAlias)
        XCTAssertEqual(AppDedupe.dedupe([alias, real]).map(\.path), ["/Applications/Foo.app"])
    }

    func testNoBundleIDFallsBackToResolvedPath() {
        let r = AppDedupe.dedupe([
            app("Foo", "/Applications/Foo.app"),
            app("Foo", "/Applications/Link/Foo.app", resolved: "/Applications/Foo.app"),
            app("Bar", "/Applications/Bar.app"),
        ])
        XCTAssertEqual(r.map(\.path), ["/Applications/Foo.app", "/Applications/Bar.app"])
    }

    func testSystemHiddenSameNameCollapsesToOne() {
        let r = AppDedupe.dedupe([
            app("Siri", "/System/Applications/Siri AI.app", id: "com.apple.campo", hidden: true),
            app("Siri", "/System/Applications/Siri.app", id: "com.apple.siri.launcher", hidden: true),
        ])
        XCTAssertEqual(r.map(\.path), ["/System/Applications/Siri.app"])
    }

    func testVisibleAppsWithSameNameButDifferentIDsAreKept() {
        let r = AppDedupe.dedupe([app("Foo", "/Applications/Foo.app", id: "a"), app("Foo", "/Applications/Foo 2.app", id: "b")])
        XCTAssertEqual(r.count, 2)
    }

    func testVersionCompare() {
        XCTAssertEqual(AppDedupe.compareVersions("1.10", "1.9"), 1)
        XCTAssertEqual(AppDedupe.compareVersions("2", "2.0.0"), 0)
        XCTAssertEqual(AppDedupe.compareVersions(nil, "1"), -1)
    }

    func testPreservesFirstSeenOrder() {
        let r = AppDedupe.dedupe([app("B", "/Applications/B.app", id: "b"), app("A", "/Applications/A.app", id: "a")])
        XCTAssertEqual(r.map(\.name), ["B", "A"])
    }
}
