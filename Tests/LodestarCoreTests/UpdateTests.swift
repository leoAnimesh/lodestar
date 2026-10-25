import XCTest
@testable import LodestarCore

final class SemanticVersionTests: XCTestCase {
    private func v(_ s: String) -> SemanticVersion { SemanticVersion(s)! }

    func testParsesPrefixesAndSuffixes() {
        XCTAssertEqual(v("v1.2.3"), SemanticVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(v("V0.1.0").core, "0.1.0")
        XCTAssertEqual(v("1.0.0-beta.2").prerelease, ["beta", "2"])
        XCTAssertEqual(v("1.0.0+build.7"), v("1.0.0"))
        XCTAssertEqual(v("1.2"), v("1.2.0"))
        XCTAssertEqual(v("2.0.0-rc.1").description, "2.0.0-rc.1")
    }

    func testRejectsGarbage() {
        for bad in ["", "v", "1", "1.2.3.4", "a.b.c", "1.-2.3", "1.2.3-", "1.2.3-be ta", "nightly", "1..2"] {
            XCTAssertNil(SemanticVersion(bad), bad)
        }
    }

    func testOrdering() {
        let ordered = ["0.1.0", "0.1.1", "0.2.0-alpha", "0.2.0-alpha.1", "0.2.0-alpha.beta", "0.2.0-beta",
                       "0.2.0-beta.2", "0.2.0-beta.11", "0.2.0-rc.1", "0.2.0", "0.10.0", "1.0.0"].map(v)
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(a, b, "\(a) < \(b)")
            XCTAssertFalse(b < a)
        }
        XCTAssertEqual(ordered.shuffled().sorted(), ordered)
    }

    func testPrefixDoesNotAffectComparison() {
        XCTAssertEqual(v("v0.3.0"), v("0.3.0"))
        XCTAssertGreaterThan(v("v0.10.0"), v("0.9.9"))
    }
}

final class ReleaseParsingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testParsesLatestRelease() throws {
        let release = try GitHubReleaseParser.parseRelease(fixture("release-latest"))
        XCTAssertEqual(release.version, SemanticVersion("0.2.0"))
        XCTAssertEqual(release.tagName, "v0.2.0")
        XCTAssertEqual(release.name, "Lodestar 0.2.0")
        XCTAssertFalse(release.isDraft)
        XCTAssertFalse(release.isPrerelease)
        XCTAssertEqual(release.htmlURL.absoluteString, "https://github.com/leoAnimesh/lodestar/releases/tag/v0.2.0")
        XCTAssertNotNil(release.publishedAt)
        XCTAssertEqual(release.assets.count, 3)
        XCTAssertTrue(release.notes.contains("What's new"))
    }

    func testAssetSelectionPrefersExactZip() throws {
        let release = try GitHubReleaseParser.parseRelease(fixture("release-latest"))
        XCTAssertEqual(release.appArchive?.name, "Lodestar-0.2.0.zip")
        XCTAssertEqual(release.appArchive?.size, 3_900_000)
        XCTAssertEqual(release.checksums?.name, "SHA256SUMS.txt")
        XCTAssertTrue(release.isInstallable)
    }

    func testAssetSelectionFallbacks() {
        let url = URL(string: "https://github.com/x")!
        func release(_ names: [String]) -> GitHubRelease {
            GitHubRelease(tagName: "v1.0.0", version: SemanticVersion("1.0.0")!, name: "", notes: "", htmlURL: url,
                          publishedAt: nil, isDraft: false, isPrerelease: false,
                          assets: names.map { ReleaseAsset(name: $0, downloadURL: url, size: 1) })
        }
        XCTAssertEqual(release(["Lodestar-v1.0.0.zip", "SHA256SUMS.txt"]).appArchive?.name, "Lodestar-v1.0.0.zip")
        XCTAssertEqual(release(["Lodestar-1.0.0-universal.zip"]).appArchive?.name, "Lodestar-1.0.0-universal.zip")
        // Two candidates and no exact name: don't guess.
        XCTAssertNil(release(["Lodestar-a.zip", "Lodestar-b.zip"]).appArchive)
        XCTAssertNil(release(["Lodestar-1.0.0.dmg"]).appArchive)
        XCTAssertFalse(release(["Lodestar-1.0.0.zip"]).isInstallable, "no checksums -> not installable")
    }

    func testListSkipsDraftsAndPrereleasesUnlessAsked() throws {
        let list = try GitHubReleaseParser.parseReleaseList(fixture("release-list"))
        XCTAssertEqual(list.count, 4, "the non-version 'nightly' tag is skipped")
        XCTAssertEqual(GitHubReleaseParser.newest(in: list, includePrereleases: false)?.tagName, "v0.2.0")
        XCTAssertEqual(GitHubReleaseParser.newest(in: list, includePrereleases: true)?.tagName, "v0.3.0-beta.2")
    }

    func testFeedParseAcceptsBothShapes() throws {
        XCTAssertEqual(try UpdateFeed.parse(fixture("release-latest"), includePrereleases: false)?.tagName, "v0.2.0")
        XCTAssertEqual(try UpdateFeed.parse(fixture("release-list"), includePrereleases: false)?.tagName, "v0.2.0")
        XCTAssertThrowsError(try UpdateFeed.parse(Data("{}".utf8), includePrereleases: false))
        XCTAssertThrowsError(try UpdateFeed.parse(Data(#"{"tag_name":"latest"}"#.utf8), includePrereleases: false))
    }

    func testDraftObjectIsNotOffered() throws {
        let draft = Data(#"{"tag_name":"v9.0.0","draft":true}"#.utf8)
        XCTAssertNil(try UpdateFeed.parse(draft, includePrereleases: true))
    }

    func testFeedResolution() {
        XCTAssertEqual(UpdateFeed.resolve(environment: [:], includePrereleases: false).url, UpdateFeed.latestURL)
        let pre = UpdateFeed.resolve(environment: [:], includePrereleases: true)
        XCTAssertEqual(pre.url, UpdateFeed.listURL)
        XCTAssertTrue(pre.isList)
        let local = UpdateFeed.resolve(environment: ["LODESTAR_UPDATE_URL": "http://127.0.0.1:8765/latest.json"],
                                       includePrereleases: false)
        XCTAssertEqual(local.url.absoluteString, "http://127.0.0.1:8765/latest.json")
        XCTAssertTrue(local.policy.allowsLoopback)
    }
}

final class UpdateDecisionTests: XCTestCase {
    private func release(_ tag: String, draft: Bool = false) -> GitHubRelease {
        GitHubRelease(tagName: tag, version: SemanticVersion(tag)!, name: tag, notes: "",
                      htmlURL: URL(string: "https://github.com")!, publishedAt: nil, isDraft: draft,
                      isPrerelease: SemanticVersion(tag)!.isPrerelease, assets: [])
    }
    private let current = SemanticVersion("0.2.0")!

    func testNewerIsAvailable() {
        XCTAssertEqual(UpdateDecision.evaluate(current: current, candidate: release("v0.3.0"), skippedVersion: nil, userInitiated: false),
                       .available(release("v0.3.0")))
    }

    func testSameOrOlderIsUpToDate() {
        for tag in ["v0.2.0", "v0.1.9", "v0.2.0-rc.1"] {
            XCTAssertEqual(UpdateDecision.evaluate(current: current, candidate: release(tag), skippedVersion: nil, userInitiated: true), .upToDate, tag)
        }
        XCTAssertEqual(UpdateDecision.evaluate(current: current, candidate: nil, skippedVersion: nil, userInitiated: true), .upToDate)
    }

    func testDraftsAreIgnored() {
        XCTAssertEqual(UpdateDecision.evaluate(current: current, candidate: release("v1.0.0", draft: true), skippedVersion: nil, userInitiated: true), .upToDate)
    }

    func testSkippedVersionOnlyHidesAutomaticChecks() {
        let r = release("v0.3.0")
        XCTAssertEqual(UpdateDecision.evaluate(current: current, candidate: r, skippedVersion: "0.3.0", userInitiated: false), .skipped(r))
        XCTAssertEqual(UpdateDecision.evaluate(current: current, candidate: r, skippedVersion: "0.3.0", userInitiated: true), .available(r))
        // Skipping 0.3.0 doesn't hide 0.3.1.
        let r2 = release("v0.3.1")
        XCTAssertEqual(UpdateDecision.evaluate(current: current, candidate: r2, skippedVersion: "0.3.0", userInitiated: false), .available(r2))
    }

    func testCheckSchedule() {
        let now = Date()
        XCTAssertTrue(UpdateDecision.isCheckDue(lastCheck: nil, now: now))
        XCTAssertFalse(UpdateDecision.isCheckDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(UpdateDecision.isCheckDue(lastCheck: now.addingTimeInterval(-86_401), now: now))
        XCTAssertTrue(UpdateDecision.isCheckDue(lastCheck: now.addingTimeInterval(86_400 * 3), now: now), "clock moved back")
    }
}

final class ChecksumTests: XCTestCase {
    let a = String(repeating: "a", count: 64)
    let b = String(repeating: "B", count: 64)

    func testParsesShasumFormats() {
        let list = ChecksumList("""
        \(a)  Lodestar-0.2.0.zip
        \(b) *Lodestar-0.2.0.dmg
        \(a)  build/release/other.txt

        not a checksum line
        """)
        XCTAssertEqual(list.digest(for: "Lodestar-0.2.0.zip"), a)
        XCTAssertEqual(list.digest(for: "Lodestar-0.2.0.dmg"), b.lowercased())
        XCTAssertEqual(list.digest(for: "other.txt"), a)
        XCTAssertNil(list.digest(for: "missing.zip"))
    }

    func testConflictingEntriesFailClosed() {
        let list = ChecksumList("\(a)  x.zip\n\(b)  x.zip\n")
        XCTAssertNil(list.digest(for: "x.zip"))
    }

    func testRejectsShortOrNonHex() {
        let list = ChecksumList("abc  x.zip\n\(String(repeating: "z", count: 64))  y.zip\n")
        XCTAssertTrue(list.digests.isEmpty)
    }

    func testFileDigest() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lodestar-sha-\(UUID().uuidString)")
        try Data("hello\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try SHA256File.hexDigest(of: url), "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03")
    }

    func testHostPolicy() {
        let policy = UpdateHostPolicy()
        XCTAssertTrue(policy.allows(URL(string: "https://api.github.com/repos/x")!))
        XCTAssertTrue(policy.allows(URL(string: "https://objects.githubusercontent.com/a")!))
        XCTAssertFalse(policy.allows(URL(string: "http://api.github.com/repos/x")!))
        XCTAssertFalse(policy.allows(URL(string: "https://evil.example.com/a")!))
        XCTAssertFalse(policy.allows(URL(string: "https://github.com.evil.com/a")!))
        XCTAssertFalse(policy.allows(URL(string: "https://user:pw@github.com/a")!))
        XCTAssertFalse(policy.allows(URL(string: "https://github.com:8443/a")!))
        XCTAssertFalse(policy.allows(URL(string: "http://127.0.0.1:8000/a")!))
        XCTAssertTrue(UpdateHostPolicy(allowsLoopback: true).allows(URL(string: "http://127.0.0.1:8000/a")!))
        XCTAssertFalse(UpdateHostPolicy(allowsLoopback: true).allows(URL(string: "http://10.0.0.1/a")!))
    }
}

final class ReleaseNotesTests: XCTestCase {
    func testBlocks() {
        let blocks = ReleaseNotes.blocks(from: """
        ## What's new
        - **Clipboard** pins survive restarts
        * Faster app search
        1. Numbered item

        A paragraph
        that wraps.
        <!-- hidden
        comment -->
        <details>
        <summary>All changes</summary>
        </details>
        """)
        XCTAssertEqual(blocks, [
            .heading(level: 2, text: "What's new"),
            .bullet(text: "**Clipboard** pins survive restarts"),
            .bullet(text: "Faster app search"),
            .bullet(text: "Numbered item"),
            .paragraph(text: "A paragraph that wraps."),
            .paragraph(text: "All changes"),
        ])
    }
}

final class AppReplacerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lodestar-replacer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func fakeApp(at url: URL, id: String = "io.github.lodestar-launcher", version: String = "0.2.0") throws -> URL {
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": version]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
        try Data(version.utf8).write(to: url.appendingPathComponent("Contents/MacOS/Lodestar"))
        return url
    }

    private func marker(_ app: URL) throws -> String {
        try String(contentsOf: app.appendingPathComponent("Contents/MacOS/Lodestar"), encoding: .utf8)
    }

    func testInstallProblems() throws {
        let replacer = AppReplacer()
        let installed = try fakeApp(at: root.appendingPathComponent("Applications/Lodestar.app"))
        XCTAssertNil(replacer.installProblem(for: installed))
        XCTAssertEqual(replacer.installProblem(for: root.appendingPathComponent("nope.app")), .notAnAppBundle)
        XCTAssertEqual(replacer.installProblem(for: root.appendingPathComponent("Applications")), .notAnAppBundle)

        // <repo>/build/Lodestar.app next to Package.swift is a dev build.
        let repo = root.appendingPathComponent("repo")
        let dev = try fakeApp(at: repo.appendingPathComponent("build/Lodestar.app"))
        try Data().write(to: repo.appendingPathComponent("Package.swift"))
        XCTAssertEqual(replacer.installProblem(for: dev), .developmentBuild)
        let dotBuild = try fakeApp(at: root.appendingPathComponent(".build/release/Lodestar.app"))
        XCTAssertEqual(replacer.installProblem(for: dotBuild), .developmentBuild)
    }

    func testFindAndValidate() throws {
        let replacer = AppReplacer()
        let staging = root.appendingPathComponent("staging")
        let app = try fakeApp(at: staging.appendingPathComponent("Lodestar.app"))
        XCTAssertEqual(try replacer.findApp(in: staging).lastPathComponent, "Lodestar.app")
        XCTAssertNoThrow(try replacer.validate(app: app, bundleIdentifier: "io.github.lodestar-launcher", version: SemanticVersion("v0.2.0")!))
        XCTAssertThrowsError(try replacer.validate(app: app, bundleIdentifier: "com.example.other", version: SemanticVersion("0.2.0")!)) {
            XCTAssertEqual($0 as? BundleValidationError, .wrongBundleIdentifier("io.github.lodestar-launcher"))
        }
        XCTAssertThrowsError(try replacer.validate(app: app, bundleIdentifier: "io.github.lodestar-launcher", version: SemanticVersion("0.3.0")!)) {
            XCTAssertEqual($0 as? BundleValidationError, .wrongVersion(expected: "0.3.0", found: "0.2.0"))
        }
        try fakeApp(at: staging.appendingPathComponent("Other.app"))
        XCTAssertThrowsError(try replacer.findApp(in: staging)) { XCTAssertEqual($0 as? BundleValidationError, .multipleApps) }
        XCTAssertThrowsError(try replacer.findApp(in: root.appendingPathComponent("empty"))) {
            XCTAssertEqual($0 as? BundleValidationError, .missingApp)
        }
    }

    func testReplaceSwapsAndReturnsBackup() throws {
        let current = try fakeApp(at: root.appendingPathComponent("Applications/Lodestar.app"), version: "0.1.0")
        let staged = try fakeApp(at: root.appendingPathComponent("staging/Lodestar.app"), version: "0.2.0")
        let backup = try AppReplacer().replace(currentApp: current, with: staged, backupDirectory: root.appendingPathComponent("backup"))
        XCTAssertEqual(try marker(current), "0.2.0")
        XCTAssertEqual(try marker(backup), "0.1.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    }

    func testFailedInstallRestoresOldApp() throws {
        let current = try fakeApp(at: root.appendingPathComponent("Applications/Lodestar.app"), version: "0.1.0")
        let staged = try fakeApp(at: root.appendingPathComponent("staging/Lodestar.app"), version: "0.2.0")
        struct Boom: Error {}
        var calls = 0
        let replacer = AppReplacer(move: { from, to in
            calls += 1
            if calls == 2 { throw Boom() }   // moving the new app in fails
            try FileManager.default.moveItem(at: from, to: to)
        })
        XCTAssertThrowsError(try replacer.replace(currentApp: current, with: staged, backupDirectory: root.appendingPathComponent("backup"))) {
            guard case .installFailedRestored = $0 as? ReplaceError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(try marker(current), "0.1.0", "old app is back in place")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
    }

    func testFailedMoveAsideLeavesEverything() throws {
        let current = try fakeApp(at: root.appendingPathComponent("Applications/Lodestar.app"), version: "0.1.0")
        let staged = try fakeApp(at: root.appendingPathComponent("staging/Lodestar.app"), version: "0.2.0")
        struct Boom: Error {}
        let replacer = AppReplacer(move: { _, _ in throw Boom() })
        XCTAssertThrowsError(try replacer.replace(currentApp: current, with: staged, backupDirectory: root.appendingPathComponent("backup")))
        XCTAssertEqual(try marker(current), "0.1.0")
    }
}
