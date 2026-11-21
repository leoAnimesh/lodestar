import XCTest
@testable import LodestarCore

final class CurrencyTests: XCTestCase {
    func testParse() {
        typealias Q = CurrencyConverter.Query
        XCTAssertEqual(CurrencyConverter.parse("100 usd to eur"), Q(amount: 100, from: "USD", to: "EUR"))
        XCTAssertEqual(CurrencyConverter.parse("1,250.5 GBP in inr"), Q(amount: 1250.5, from: "GBP", to: "INR"))
        XCTAssertEqual(CurrencyConverter.parse("$20"), Q(amount: 20, from: "USD", to: nil))
        XCTAssertEqual(CurrencyConverter.parse("$20 eur"), Q(amount: 20, from: "USD", to: "EUR"))
        XCTAssertEqual(CurrencyConverter.parse("50€"), Q(amount: 50, from: "EUR", to: nil))
        XCTAssertEqual(CurrencyConverter.parse("10 eur usd"), Q(amount: 10, from: "EUR", to: "USD"))
        XCTAssertNil(CurrencyConverter.parse("100"))
        XCTAssertNil(CurrencyConverter.parse("safari"))
        XCTAssertNil(CurrencyConverter.parse("2 + 3"))
        XCTAssertNil(CurrencyConverter.parse("$1 eur to gbp"))
    }

    func testConvert() {
        let rates = ["USD": 1, "EUR": 0.5, "INR": 80.0]
        XCTAssertEqual(CurrencyConverter.convert(10, from: "USD", to: "EUR", rates: rates), 5)
        XCTAssertEqual(CurrencyConverter.convert(10, from: "EUR", to: "INR", rates: rates), 1600)
        XCTAssertNil(CurrencyConverter.convert(10, from: "MIN", to: "USD", rates: rates))
    }

    func testDecode() {
        let json = #"{"result":"success","base_code":"USD","rates":{"USD":1,"EUR":0.92}}"#
        XCTAssertEqual(CurrencyConverter.decodeRates(Data(json.utf8))?["EUR"], 0.92)
        XCTAssertNil(CurrencyConverter.decodeRates(Data(#"{"result":"error","rates":{}}"#.utf8)))
    }
}

final class TypingTestTests: XCTestCase {
    func testScoring() {
        let t = TypingTest("hello world")
        XCTAssertEqual(t.states(typed: "hex").prefix(4), [.correct, .correct, .wrong, .pending])
        XCTAssertEqual(t.accuracy(typed: "hex"), 66)
        XCTAssertEqual(t.accuracy(typed: ""), 100)
        XCTAssertFalse(t.isDone(typed: "hello"))
        XCTAssertTrue(t.isDone(typed: "hello world"))
        // 10 correct chars = 2 words in 6s -> 20 wpm
        XCTAssertEqual(t.wpm(typed: "hello worlx", elapsed: 6), 20)
    }
}
