import XCTest
import AppKit
@testable import LodestarCore

final class ColorFormatTests: XCTestCase {
    let blue = SRGBColor(red: 58, green: 123, blue: 255)

    func testFormats() {
        XCTAssertEqual(blue.hex, "#3A7BFF")
        XCTAssertEqual(blue.cssRGB, "rgb(58, 123, 255)")
        XCTAssertEqual(blue.cssHSL, "hsl(220, 100%, 61%)")
        XCTAssertEqual(blue.swiftUI, "Color(red: 0.227, green: 0.482, blue: 1.000)")
        XCTAssertEqual(blue.nsColor, "NSColor(srgbRed: 0.227, green: 0.482, blue: 1.000, alpha: 1.0)")
        XCTAssertEqual(ColorFormat.allCases.map { $0.string(for: blue) },
                       [blue.hex, blue.cssRGB, blue.cssHSL, blue.swiftUI, blue.nsColor])
    }

    func testHexParsing() {
        XCTAssertEqual(SRGBColor(hex: "#3A7BFF"), blue)
        XCTAssertEqual(SRGBColor(hex: " 3a7bff\n"), blue)
        XCTAssertEqual(SRGBColor(hex: "#38F"), SRGBColor(red: 0x33, green: 0x88, blue: 0xFF))
        for bad in ["", "#", "#12345", "#1234567", "#GG0000", "+3A7BFF"] {
            XCTAssertNil(SRGBColor(hex: bad), bad)
        }
        XCTAssertEqual(SRGBColor(red: 0, green: 0, blue: 0).hex, "#000000")
        XCTAssertEqual(SRGBColor(red: 255, green: 255, blue: 255).hex, "#FFFFFF")
    }

    func testHSLEdgeCases() {
        XCTAssertEqual(SRGBColor(red: 255, green: 0, blue: 0).cssHSL, "hsl(0, 100%, 50%)")
        XCTAssertEqual(SRGBColor(red: 0, green: 255, blue: 0).cssHSL, "hsl(120, 100%, 50%)")
        XCTAssertEqual(SRGBColor(red: 0, green: 0, blue: 255).cssHSL, "hsl(240, 100%, 50%)")
        XCTAssertEqual(SRGBColor(red: 255, green: 0, blue: 128).cssHSL, "hsl(330, 100%, 50%)", "negative hue wraps")
        XCTAssertEqual(SRGBColor(red: 128, green: 128, blue: 128).cssHSL, "hsl(0, 0%, 50%)", "grays have no hue")
        XCTAssertEqual(SRGBColor(red: 0, green: 0, blue: 0).cssHSL, "hsl(0, 0%, 0%)")
        XCTAssertEqual(SRGBColor(red: 255, green: 255, blue: 255).cssHSL, "hsl(0, 0%, 100%)")
        // Hue that would round up to 360 reads as 0.
        XCTAssertEqual(SRGBColor(red: 255, green: 0, blue: 1).cssHSL, "hsl(0, 100%, 50%)")
    }

    func testQuantizeClampsOutOfGamut() {
        XCTAssertEqual(SRGBColor(srgbRed: 1.2, green: -0.1, blue: 0.5), SRGBColor(red: 255, green: 0, blue: 128))
        XCTAssertEqual(SRGBColor(srgbRed: .nan, green: .infinity, blue: 0.2275), SRGBColor(red: 0, green: 0, blue: 58))
    }

    func testTransferFunctionRoundTrips() {
        for c in stride(from: -0.5, through: 1.5, by: 0.05) {
            XCTAssertEqual(SRGBColor.linearToSRGB(SRGBColor.srgbToLinear(c)), c, accuracy: 1e-9)
        }
    }

    func testDisplayP3ToSRGB() {
        // Neutral colors are identical in both spaces (same white point and curve).
        XCTAssertEqual(SRGBColor.fromDisplayP3(red: 1, green: 1, blue: 1), SRGBColor(red: 255, green: 255, blue: 255))
        XCTAssertEqual(SRGBColor.fromDisplayP3(red: 0.5, green: 0.5, blue: 0.5), SRGBColor(red: 128, green: 128, blue: 128))
        // P3 primaries lie outside sRGB: the unclamped red goes past 1 and the
        // others below 0, then clamp to pure sRGB red.
        let (r, g, b) = SRGBColor.displayP3ToSRGBComponents(red: 1, green: 0, blue: 0)
        XCTAssertEqual(r, 1.0930, accuracy: 0.001)
        XCTAssertEqual(g, -0.2267, accuracy: 0.001)
        XCTAssertEqual(b, -0.1501, accuracy: 0.001)
        XCTAssertEqual(SRGBColor.fromDisplayP3(red: 1, green: 0, blue: 0), SRGBColor(red: 255, green: 0, blue: 0))
    }

    /// Our P3 math must agree with ColorSync (what NSColor uses) for in-gamut colors.
    func testDisplayP3MatchesAppKit() {
        let samples: [(Double, Double, Double)] = [(0.30, 0.50, 0.90), (0.80, 0.40, 0.20), (0.25, 0.60, 0.35), (0.9, 0.85, 0.7)]
        for (r, g, b) in samples {
            // AppKit's .sRGB conversion clamps out-of-gamut colors (the third
            // sample is one), so compare the clamped values.
            let ours = SRGBColor.displayP3ToSRGBComponents(red: r, green: g, blue: b)
            let clamp = { (v: Double) in min(max(v, 0), 1) }
            guard let ns = NSColor(displayP3Red: r, green: g, blue: b, alpha: 1).usingColorSpace(.sRGB) else {
                return XCTFail("conversion failed")
            }
            XCTAssertEqual(clamp(ours.0), Double(ns.redComponent), accuracy: 0.003)
            XCTAssertEqual(clamp(ours.1), Double(ns.greenComponent), accuracy: 0.003)
            XCTAssertEqual(clamp(ours.2), Double(ns.blueComponent), accuracy: 0.003)
            XCTAssertEqual(SRGBColor.fromDisplayP3(red: r, green: g, blue: b),
                           SRGBColor(srgbRed: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent)))
        }
    }

    func testHistoryDedupesAndLimits() {
        var history = ColorHistory(limit: 3)
        let t = Date(timeIntervalSince1970: 1_000)
        let red = SRGBColor(red: 255, green: 0, blue: 0), green = SRGBColor(red: 0, green: 255, blue: 0)
        history.add(red, at: t)
        history.add(green, at: t.addingTimeInterval(1))
        history.add(blue, at: t.addingTimeInterval(2))
        XCTAssertEqual(history.entries.map(\.color), [blue, green, red])
        history.add(red, at: t.addingTimeInterval(3))
        XCTAssertEqual(history.entries.map(\.color), [red, blue, green], "re-picking moves to the front")
        XCTAssertEqual(history.entries.first?.date, t.addingTimeInterval(3))
        history.add(SRGBColor(red: 1, green: 2, blue: 3), at: t.addingTimeInterval(4))
        XCTAssertEqual(history.entries.count, 3)
        XCTAssertEqual(history.entries.last?.color, blue, "oldest dropped")
        history.remove(blue)
        XCTAssertEqual(history.entries.map(\.color), [SRGBColor(red: 1, green: 2, blue: 3), red])
        history.clear()
        XCTAssertNil(history.latest)
        XCTAssertEqual(ColorHistory().limit, 20)
    }

    func testHistoryPersistenceRoundTrip() throws {
        var history = ColorHistory()
        history.add(blue, at: Date(timeIntervalSince1970: 1_700_000_000))
        history.add(SRGBColor(red: 9, green: 8, blue: 7), at: Date(timeIntervalSince1970: 1_700_000_060))
        let data = try history.encoded()
        XCTAssertEqual(ColorHistory.decoded(from: data), history)
        XCTAssertEqual(ColorHistory.decoded(from: Data("garbage".utf8)).entries, [])
        XCTAssertEqual(ColorHistory.decoded(from: nil).entries, [])
        XCTAssertEqual(ColorHistory.decoded(from: data, limit: 1).entries.count, 1, "a smaller limit truncates on load")
    }
}

final class CaffeinateTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testPresetsTitlesAndIDs() {
        XCTAssertEqual(CaffeinateDuration.presets.map(\.commandTitle),
                       ["Caffeinate", "Caffeinate for 30 Minutes", "Caffeinate for 1 Hour", "Caffeinate for 2 Hours"])
        XCTAssertEqual(CaffeinateDuration.presets.map(\.commandID),
                       ["cmd:caffeinate", "cmd:caffeinate-30m", "cmd:caffeinate-1h", "cmd:caffeinate-2h"])
        XCTAssertEqual(CaffeinateDuration(seconds: 90 * 60).commandTitle, "Caffeinate for 1 Hour 30 Minutes")
        XCTAssertEqual(CaffeinateDuration(seconds: 60).commandTitle, "Caffeinate for 1 Minute")
    }

    func testTimedSessionLifecycle() {
        var state = CaffeinateState()
        XCTAssertFalse(state.isActive(at: t0))
        XCTAssertNil(state.statusText(at: t0))

        state.start(.thirtyMinutes, at: t0)
        XCTAssertTrue(state.isActive(at: t0))
        XCTAssertEqual(state.session?.endDate, t0.addingTimeInterval(1800))
        XCTAssertEqual(state.statusText(at: t0), "Active — 30m left")
        XCTAssertEqual(state.statusText(at: t0.addingTimeInterval(18 * 60 + 1)), "Active — 12m left")
        XCTAssertEqual(state.statusText(at: t0.addingTimeInterval(1799)), "Active — 1m left")
        XCTAssertFalse(state.expireIfNeeded(at: t0.addingTimeInterval(1799)))

        XCTAssertFalse(state.isActive(at: t0.addingTimeInterval(1800)), "expired exactly at the end")
        XCTAssertTrue(state.expireIfNeeded(at: t0.addingTimeInterval(1800)))
        XCTAssertNil(state.session)
        XCTAssertFalse(state.expireIfNeeded(at: t0.addingTimeInterval(1801)), "only reports the transition once")
    }

    func testIndefiniteSessionAndStop() {
        var state = CaffeinateState()
        state.start(.indefinitely, at: t0)
        let farFuture = t0.addingTimeInterval(86_400 * 365)
        XCTAssertTrue(state.isActive(at: farFuture))
        XCTAssertNil(state.session?.remaining(at: farFuture))
        XCTAssertFalse(state.expireIfNeeded(at: farFuture))
        XCTAssertEqual(state.statusText(at: farFuture), "Active — until stopped")
        XCTAssertTrue(state.stop())
        XCTAssertFalse(state.stop(), "stopping twice is a no-op")
        XCTAssertFalse(state.isActive(at: t0))
    }

    func testRestartReplacesSession() {
        var state = CaffeinateState()
        state.start(.twoHours, at: t0)
        state.start(.thirtyMinutes, at: t0.addingTimeInterval(600))
        XCTAssertEqual(state.session?.duration, .thirtyMinutes)
        XCTAssertEqual(state.statusText(at: t0.addingTimeInterval(600)), "Active — 30m left")
        XCTAssertEqual(state.statusText(at: t0), "Active — 40m left", "remaining never exceeds the duration")
    }

    func testFormatRemaining() {
        XCTAssertEqual(CaffeinateState.formatRemaining(0), "1m")
        XCTAssertEqual(CaffeinateState.formatRemaining(5), "1m")
        XCTAssertEqual(CaffeinateState.formatRemaining(42 * 60), "42m")
        XCTAssertEqual(CaffeinateState.formatRemaining(41 * 60 + 1), "42m")
        XCTAssertEqual(CaffeinateState.formatRemaining(3600), "1h")
        XCTAssertEqual(CaffeinateState.formatRemaining(3900), "1h 5m")
        XCTAssertEqual(CaffeinateState.formatRemaining(7200), "2h")
    }

    func testArrangePutsRelevantCommandFirst() {
        let ids = ["app:/Coffee.app", "cmd:caffeinate", "cmd:caffeinate-1h", "cmd:decaffeinate", "fallback:web"]
        XCTAssertEqual(CaffeinateState.arrange(ids, active: false),
                       ["app:/Coffee.app", "cmd:caffeinate", "cmd:caffeinate-1h", "fallback:web"])
        XCTAssertEqual(CaffeinateState.arrange(ids, active: true),
                       ["app:/Coffee.app", "cmd:decaffeinate", "cmd:caffeinate", "cmd:caffeinate-1h", "fallback:web"])
        XCTAssertEqual(CaffeinateState.arrange(["cmd:decaffeinate", "cmd:caffeinate"], active: true),
                       ["cmd:decaffeinate", "cmd:caffeinate"], "already first")
        XCTAssertEqual(CaffeinateState.arrange(["cmd:caffeinate-2h"], active: true), ["cmd:caffeinate-2h"])
        XCTAssertTrue(CaffeinateState.isCaffeinateID("cmd:caffeinate-30m"))
        XCTAssertFalse(CaffeinateState.isCaffeinateID("cmd:decaffeinate"))
    }
}
