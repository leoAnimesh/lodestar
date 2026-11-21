import Foundation
import LodestarCore

/// Exchange rates (per 1 USD) from open.er-api.com, fetched on first use and
/// refreshed after 6 hours. Main thread only.
/// shortcut: memory-only cache, so offline right after launch shows no conversion; persist to disk if that matters.
final class CurrencyRates {
    private(set) var rates: [String: Double]?
    private var fetchedAt = Date.distantPast
    private var loading = false

    /// Calls `onLoad` once fresh rates arrive (only if a fetch was needed).
    func refreshIfStale(onLoad: @escaping () -> Void) {
        guard !loading, Date().timeIntervalSince(fetchedAt) > 6 * 3600 else { return }
        loading = true
        let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let decoded = data.flatMap(CurrencyConverter.decodeRates)
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                guard let decoded else { return }
                self.rates = decoded
                self.fetchedAt = Date()
                onLoad()
            }
        }.resume()
    }

    /// A launcher row for "100 usd to eur", or nil when it isn't a conversion
    /// (or rates aren't loaded yet; `onLoad` re-runs the search when they are).
    func item(for query: String, onLoad: @escaping () -> Void) -> LauncherItem? {
        guard let q = CurrencyConverter.parse(query) else { return nil }
        refreshIfStale(onLoad: onLoad)
        guard let rates else { return nil }
        let local = Locale.current.currency?.identifier ?? "USD"
        let to = q.to ?? (q.from == local ? (local == "USD" ? "EUR" : "USD") : local)
        guard let value = CurrencyConverter.convert(q.amount, from: q.from, to: to, rates: rates) else { return nil }
        let plain = String(format: "%.2f", value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = to
        let pretty = formatter.string(from: NSNumber(value: value)) ?? "\(plain) \(to)"
        return LauncherItem(
            id: "currency", title: pretty, subtitle: "= \(Calculator.format(q.amount)) \(q.from)", icon: .symbol("dollarsign.arrow.circlepath"),
            accessory: "\(q.from) → \(to)",
            actions: [
                LauncherAction("Copy Result", symbol: "doc.on.doc") { SystemActions.copy(plain); return .close },
                LauncherAction("Paste Result", symbol: "doc.on.clipboard") { .closeThen { SystemActions.paste(plain) } },
            ],
            tracksUsage: false
        )
    }
}
