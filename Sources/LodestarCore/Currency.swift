import Foundation

/// Parses "100 usd to eur", "$100 in inr", "50€", "20 gbp" and converts with
/// a rates table (units per 1 of a common base, e.g. USD).
public enum CurrencyConverter {
    public struct Query: Equatable {
        public let amount: Double
        public let from: String
        /// nil: the caller picks a default (the user's local currency).
        public let to: String?
    }

    static let symbols: [String: String] = ["$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₹": "INR", "₩": "KRW", "₽": "RUB"]

    private static let pattern = try! NSRegularExpression(
        pattern: #"^([$€£¥₹₩₽])?\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s*([a-z]{3}|[$€£¥₹₩₽])?\s*(?:(?:to|in|as|=)\s+)?([a-z]{3}|[$€£¥₹₩₽])?$"#,
        options: [.caseInsensitive])

    public static func parse(_ input: String) -> Query? {
        let s = input.trimmingCharacters(in: .whitespaces)
        let ns = s as NSString
        guard let m = pattern.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        func code(_ raw: String?) -> String? { raw.map { symbols[$0] ?? $0.uppercased() } }
        guard let amount = Double(group(2)!.replacingOccurrences(of: ",", with: "")) else { return nil }
        let prefix = code(group(1)), unit = code(group(3)), target = code(group(4))
        // "$100 eur": the prefix is the source and the unit the target.
        if let prefix {
            if unit != nil, target != nil { return nil }
            return Query(amount: amount, from: prefix, to: unit ?? target)
        }
        guard let unit else { return nil }
        return Query(amount: amount, from: unit, to: target)
    }

    /// nil when either code isn't in `rates`.
    public static func convert(_ amount: Double, from: String, to: String, rates: [String: Double]) -> Double? {
        guard let f = rates[from], let t = rates[to], f > 0 else { return nil }
        return amount / f * t
    }

    /// Decodes an open.er-api.com `/v6/latest/<base>` response.
    public static func decodeRates(_ data: Data) -> [String: Double]? {
        struct Response: Decodable { let result: String; let rates: [String: Double] }
        guard let r = try? JSONDecoder().decode(Response.self, from: data), r.result == "success" else { return nil }
        return r.rates
    }
}
