import XCTest
@testable import LodestarCore

final class AppUninstallTests: XCTestCase {
    func testSystemAppsAreProtected() {
        XCTAssertTrue(AppUninstall.isProtected(path: "/System/Applications/Safari.app", bundleID: "com.apple.Safari"))
        XCTAssertFalse(AppUninstall.isProtected(path: "/Applications/Xcode.app", bundleID: "com.apple.dt.Xcode"))
        XCTAssertFalse(AppUninstall.isProtected(path: "/Applications/Foo.app", bundleID: "com.foo.app"))
    }

    func testRelatedPaths() {
        let paths = AppUninstall.relatedPaths(bundleID: "com.foo.app", name: "Foo", home: "/Users/x")
        XCTAssertTrue(paths.contains("/Users/x/Library/Preferences/com.foo.app.plist"))
        XCTAssertTrue(paths.contains("/Users/x/Library/Application Support/Foo"))
        XCTAssertEqual(paths.count, Set(paths).count)
        XCTAssertTrue(AppUninstall.relatedPaths(bundleID: nil, name: "a/b", home: "/h").isEmpty)
    }

    func testSymlinkIntoSystemIsProtected() throws {
        // Like /Applications/Safari.app -> /System/Cryptexes/...: looks user-installed, isn't.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let link = dir.appendingPathComponent("Calculator.app").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/System/Applications/Calculator.app")
        XCTAssertTrue(AppUninstall.isProtected(path: link, bundleID: "com.apple.calculator"))
    }

    func testUnsafeNamesNeverEscapeLibrary() {
        for bad in ["..", ".", "", "a/b", "../.."] {
            XCTAssertTrue(AppUninstall.relatedPaths(bundleID: bad, name: bad, home: "/Users/x").isEmpty, bad)
        }
        XCTAssertTrue(AppUninstall.isSafePathComponent("com.foo.app"))
        XCTAssertTrue(AppUninstall.isSafePathComponent("Foo Bar"))
    }
}
