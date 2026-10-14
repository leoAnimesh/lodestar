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

    func testDisplaySymbols() {
        XCTAssertEqual(HotkeySpec.default.description, "⌥Space")
        XCTAssertEqual(HotkeySpec("ctrl+option+shift+cmd+f5")?.description, "⌃⌥⇧⌘F5")
        XCTAssertEqual(HotkeySpec("cmd+esc")?.description, "⌘⎋")
        XCTAssertEqual(HotkeySpec("option+return")?.description, "⌥↩")
        XCTAssertEqual(HotkeySpec("ctrl+left")?.description, "⌃←")
        XCTAssertEqual(HotkeySpec("cmd+minus")?.description, "⌘-")
        XCTAssertEqual(HotkeySpec.displayName(forKeyCode: 40), "K")
    }

    func testConfigStringRoundTrips() {
        XCTAssertEqual(HotkeySpec.default.configString, "option+space")
        XCTAssertEqual(HotkeySpec("cmd+shift+k")?.configString, "shift+cmd+k")
        XCTAssertEqual(HotkeySpec("alt+esc")?.configString, "option+escape")
        // Every key the recorder can produce must survive a save/load cycle.
        for (code, _) in HotkeySpec.canonicalNames {
            for mods in [HotkeySpec.command, HotkeySpec.option | HotkeySpec.shift, HotkeySpec.control | HotkeySpec.command] {
                let spec = HotkeySpec(keyCode: code, carbonModifiers: mods)!
                XCTAssertEqual(HotkeySpec(spec.configString), spec, spec.configString)
            }
        }
    }

    func testCocoaFlagConversionIgnoresOtherBits() {
        let capsLock: UInt = 1 << 16, function: UInt = 1 << 23, deviceBits: UInt = 0x120
        let flags = HotkeySpec.cocoaCommand | HotkeySpec.cocoaShift | capsLock | function | deviceBits
        XCTAssertEqual(HotkeySpec.carbonModifiers(cocoaFlags: flags), HotkeySpec.command | HotkeySpec.shift)
        XCTAssertEqual(HotkeySpec.carbonModifiers(cocoaFlags: HotkeySpec.cocoaOption | HotkeySpec.cocoaControl),
                       HotkeySpec.option | HotkeySpec.control)
    }

    func testValidation() {
        XCTAssertEqual(HotkeySpec.validate(keyCode: 49, carbonModifiers: HotkeySpec.option), .success(.default))
        XCTAssertEqual(HotkeySpec.validate(keyCode: 40, carbonModifiers: 0), .failure(.needsModifier))
        XCTAssertEqual(HotkeySpec.validate(keyCode: 40, carbonModifiers: HotkeySpec.shift), .failure(.needsModifier))
        XCTAssertEqual(HotkeySpec.validate(keyCode: 96, carbonModifiers: 0), .failure(.needsModifier)) // bare F5
        XCTAssertEqual(HotkeySpec.validate(keyCode: 200, carbonModifiers: HotkeySpec.command), .failure(.unsupportedKey(200)))
        if case .success(let spec) = HotkeySpec.validate(keyCode: 40, carbonModifiers: HotkeySpec.shift | HotkeySpec.control) {
            XCTAssertEqual(spec.configString, "ctrl+shift+k")
        } else {
            XCTFail("⌃⇧K should be valid")
        }
    }

    func testRecorderOutcomes() {
        XCTAssertEqual(HotkeyRecorder.interpret(keyCode: 53, cocoaFlags: 0), .cancel)
        XCTAssertEqual(HotkeyRecorder.interpret(keyCode: 51, cocoaFlags: 0), .restoreDefault)
        XCTAssertEqual(HotkeyRecorder.interpret(keyCode: 117, cocoaFlags: 1 << 23), .restoreDefault) // ⌦ carries Fn
        XCTAssertEqual(HotkeyRecorder.interpret(keyCode: 49, cocoaFlags: HotkeySpec.cocoaOption), .record(.default))
        XCTAssertEqual(HotkeyRecorder.interpret(keyCode: 40, cocoaFlags: HotkeySpec.cocoaShift), .invalid(.needsModifier))
        XCTAssertEqual(HotkeyRecorder.interpret(keyCode: 0, cocoaFlags: 0), .invalid(.needsModifier))
        // With a modifier, Esc and Delete are ordinary keys.
        XCTAssertEqual(HotkeyRecorder.interpret(keyCode: 53, cocoaFlags: HotkeySpec.cocoaCommand), .record(HotkeySpec("cmd+escape")!))
        XCTAssertEqual(HotkeyRecorder.interpret(keyCode: 51, cocoaFlags: HotkeySpec.cocoaOption), .record(HotkeySpec("option+delete")!))
        XCTAssertEqual(HotkeyRecorder.modifierPreview(cocoaFlags: HotkeySpec.cocoaCommand | HotkeySpec.cocoaControl), "⌃⌘")
    }
}

final class ConfigTests: XCTestCase {
    func testUpdatePreservesUnknownAndUntouchedKeys() throws {
        let existing = Data(#"{"hotkey":"cmd+space","clipboardHistoryLimit":50,"theme":"dark","nested":{"a":[1,2]}}"#.utf8)
        let (data, config) = try LodestarConfig.updated(existing) { $0.hotkey = "ctrl+option+k" }
        XCTAssertEqual(config.hotkey, "ctrl+option+k")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["hotkey"] as? String, "ctrl+option+k")
        XCTAssertEqual(object["clipboardHistoryLimit"] as? Int, 50)
        XCTAssertEqual(object["theme"] as? String, "dark")
        XCTAssertNotNil(object["nested"])
        // The written file is readable by the existing loader and parser.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lodestar-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let loaded = LodestarConfig.load(from: url)
        XCTAssertEqual(loaded.hotkey.flatMap(HotkeySpec.init), HotkeySpec("ctrl+option+k"))
        XCTAssertEqual(loaded.clipboardHistoryLimit, 50)
    }

    func testUpdateRemovesClearedKey() throws {
        let existing = Data(#"{"hotkey":"cmd+space","clipboardHistoryEnabled":false}"#.utf8)
        let (data, _) = try LodestarConfig.updated(existing) { $0.hotkey = nil }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["hotkey"])
        XCTAssertEqual(object["clipboardHistoryEnabled"] as? Bool, false)
    }

    func testUpdateCreatesFileFromNothingOrWhitespace() throws {
        for existing in [nil, Data(), Data("  \n".utf8)] {
            let (data, config) = try LodestarConfig.updated(existing) { $0.clipboardHistoryEnabled = true }
            XCTAssertEqual(config, LodestarConfig(clipboardHistoryEnabled: true))
            XCTAssertEqual(try JSONDecoder().decode(LodestarConfig.self, from: data), config)
        }
    }

    func testUpdateRefusesToOverwriteInvalidFile() {
        for bad in [#"{"hotkey": "#, #"[1,2]"#, #"{"clipboardHistoryLimit":"lots"}"#] {
            XCTAssertThrowsError(try LodestarConfig.updated(Data(bad.utf8)) { $0.hotkey = "cmd+k" }) {
                XCTAssertEqual($0 as? ConfigError, .invalidFile)
            }
        }
    }

    func testUpdateWritesAtomicallyToDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lodestar-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try LodestarConfig.update(at: url) { $0.hotkey = HotkeySpec.default.configString }
        try LodestarConfig.update(at: url) { $0.clipboardHistoryLimit = 100 }
        XCTAssertEqual(LodestarConfig.load(from: url), LodestarConfig(hotkey: "option+space", clipboardHistoryLimit: 100))
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
