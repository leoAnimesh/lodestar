import XCTest
@testable import LodestarCore

final class FuzzyMatcherTests: XCTestCase {
    func testSubsequenceMatches() {
        XCTAssertNotNil(FuzzyMatcher.match("sfr", in: "Safari"))
        XCTAssertNil(FuzzyMatcher.match("xyz", in: "Safari"))
    }

    func testWordStartsBeatScatteredLetters() {
        let acronym = FuzzyMatcher.match("vsc", in: "Visual Studio Code")!
        let scattered = FuzzyMatcher.match("vsc", in: "Discovery Services")
        XCTAssertGreaterThan(acronym.score, scattered?.score ?? -.infinity)
        XCTAssertEqual(acronym.matchedIndices, [0, 7, 14])
    }

    func testPrefixAndExactRankHighest() {
        let exact = FuzzyMatcher.match("notes", in: "Notes")!.score
        let prefix = FuzzyMatcher.match("notes", in: "Notes Helper")!.score
        let inner = FuzzyMatcher.match("notes", in: "Sticky Notes")!.score
        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, inner)
    }

    func testRankerOrdersByScoreAndFrecency() {
        let candidates = [
            SearchCandidate(id: "a", title: "Terminal"),
            SearchCandidate(id: "b", title: "TextEdit"),
            SearchCandidate(id: "c", title: "Calendar"),
        ]
        let store = FrecencyStore(url: nil)
        var ranked = Ranker.rank(candidates, query: "te", frecency: store)
        XCTAssertEqual(ranked.map(\.candidate.id).sorted(), ["a", "b"])
        for _ in 0..<20 { store.recordUse(of: "a") }
        ranked = Ranker.rank(candidates, query: "te", frecency: store)
        XCTAssertEqual(ranked.first?.candidate.id, "a")
    }
}

final class CalculatorTests: XCTestCase {
    func eval(_ s: String) throws -> Double { try Calculator.evaluate(s) }

    func testPrecedenceAndAssociativity() throws {
        XCTAssertEqual(try eval("2 + 3 * 4"), 14)
        XCTAssertEqual(try eval("(2 + 3) * 4"), 20)
        XCTAssertEqual(try eval("2^3^2"), 512)
        XCTAssertEqual(try eval("-2^2"), -4)
        XCTAssertEqual(try eval("2^-1"), 0.5)
        XCTAssertEqual(try eval("10 % 4"), 2)
    }

    func testFunctionsConstantsAndImplicitMultiplication() throws {
        XCTAssertEqual(try eval("sqrt(16)"), 4)
        XCTAssertEqual(try eval("2pi"), 2 * .pi, accuracy: 1e-12)
        XCTAssertEqual(try eval("2(3+4)"), 14)
        XCTAssertEqual(try eval("5!"), 120)
        XCTAssertEqual(try eval("3 x 4"), 12)
        XCTAssertEqual(try eval("2x3"), 6)
        XCTAssertEqual(try eval("1,000 * 2"), 2000)
        XCTAssertEqual(try eval("1.5e3"), 1500)
        XCTAssertEqual(try eval("log2(8)"), 3)
    }

    func testRejectsNonCalculations() {
        XCTAssertNil(Calculator.evaluateIfCalculation("safari"))
        XCTAssertNil(Calculator.evaluateIfCalculation("42"))
        XCTAssertNil(Calculator.evaluateIfCalculation("2 +"))
        XCTAssertNil(Calculator.evaluateIfCalculation("1/0"))
        XCTAssertEqual(Calculator.evaluateIfCalculation("1/4"), 0.25)
    }

    func testFormatting() {
        XCTAssertEqual(Calculator.format(0.1 + 0.2), "0.3")
        XCTAssertEqual(Calculator.format(42), "42")
        XCTAssertEqual(Calculator.format(-3), "-3")
    }
}

final class HotkeySpecTests: XCTestCase {
    func testParsing() {
        let spec = HotkeySpec("option+space")
        XCTAssertEqual(spec, HotkeySpec.default)
        let k = HotkeySpec("cmd+shift+k")!
        XCTAssertEqual(k.keyCode, 40)
        XCTAssertEqual(k.carbonModifiers, HotkeySpec.command | HotkeySpec.shift)
        XCTAssertEqual(k.description, "⇧⌘K")
        XCTAssertNil(HotkeySpec("k"))
        XCTAssertNil(HotkeySpec("hyper+k"))
        XCTAssertNotNil(HotkeySpec("f5"))
    }
}

final class ScriptCommandTests: XCTestCase {
    func testParsesMetadata() {
        let script = """
        #!/bin/bash
        # @lodestar.schemaVersion 1
        # @lodestar.title Say Hello
        # @lodestar.mode fullOutput
        # @lodestar.icon 👋
        # @lodestar.keywords greet, hi
        # @lodestar.argument1 { "type": "text", "placeholder": "Name" }
        echo hello
        """
        let cmd = ScriptCommand.parse(contents: script, path: "/tmp/x.sh")!
        XCTAssertEqual(cmd.title, "Say Hello")
        XCTAssertEqual(cmd.mode, .fullOutput)
        XCTAssertEqual(cmd.icon, "👋")
        XCTAssertEqual(cmd.keywords, ["greet", "hi"])
        XCTAssertTrue(cmd.needsArgument)
        XCTAssertEqual(cmd.argumentPlaceholder, "Name")
    }

    func testCompatPrefixAndMissingTitle() {
        XCTAssertEqual(ScriptCommand.parse(contents: "// @raycast.title JS Thing\n", path: "a.js")?.title, "JS Thing")
        XCTAssertNil(ScriptCommand.parse(contents: "#!/bin/sh\necho hi\n", path: "b.sh"))
    }
}

final class ExtensionProtocolTests: XCTestCase {
    func testDecodesExtensionMessages() throws {
        let json = #"{"type":"items","items":[{"title":"A","actions":[{"type":"copy","text":"x"},{"type":"callback","id":"r"}]}]}"#
        let msg = try JSONDecoder().decode(ExtensionMessage.self, from: Data(json.utf8))
        guard case .items(let items, _) = msg else { return XCTFail("wrong case") }
        XCTAssertEqual(items.first?.actions, [.copy(text: "x"), .callback(id: "r")])
        XCTAssertEqual(try JSONDecoder().decode(ExtensionMessage.self, from: Data(#"{"type":"close"}"#.utf8)), .close)
    }

    func testEncodesHostMessages() {
        let line = String(decoding: HostMessage.run(command: "search", query: "q").encodedLine(), as: UTF8.self)
        XCTAssertEqual(line, #"{"command":"search","protocol":1,"query":"q","type":"run"}"# + "\n")
    }

    func testLineBuffer() {
        var buf = LineBuffer()
        XCTAssertEqual(buf.append(Data("{\"a\":1}\n{\"b\"".utf8)).count, 1)
        let rest = buf.append(Data(":2}\n\n".utf8))
        XCTAssertEqual(rest.map { String(decoding: $0, as: UTF8.self) }, ["{\"b\":2}"])
    }

    func testManifestDecoding() throws {
        let json = #"{"name":"x","title":"X","run":["node","index.js"],"commands":[{"name":"s","title":"Search","mode":"list"},{"name":"n","title":"Now","mode":"no-view"}]}"#
        let m = try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
        XCTAssertEqual(m.commands.map(\.mode), [.list, .noView])
    }
}

/// End-to-end check of the wire protocol against the bundled Node example,
/// skipped when Node.js isn't installed.
final class NodeExtensionIntegrationTests: XCTestCase {
    func testEmojiExampleSpeaksTheProtocol() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let extDir = repo.appendingPathComponent("Examples/extensions/emoji-search")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "index.js"]
        process.currentDirectoryURL = extDir
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin"
        process.environment = env
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw XCTSkip("node not available") }

        stdin.fileHandleForWriting.write(HostMessage.run(command: "search", query: "").encodedLine())
        stdin.fileHandleForWriting.write(HostMessage.query(text: "rocket").encodedLine())
        try stdin.fileHandleForWriting.close()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus == 127 { throw XCTSkip("node not on PATH") }

        var buffer = LineBuffer()
        let messages = try buffer.append(data).map { try JSONDecoder().decode(ExtensionMessage.self, from: $0) }
        XCTAssertEqual(messages.count, 2)
        guard case .items(let filtered, _) = messages.last else { return XCTFail("expected items") }
        XCTAssertEqual(filtered.map(\.title), ["rocket"])
        XCTAssertEqual(filtered.first?.actions?.first, .paste(text: "🚀"))
    }
}
