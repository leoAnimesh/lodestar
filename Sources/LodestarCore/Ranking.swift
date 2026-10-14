import Foundation

/// Anything that can be searched from the root launcher.
public struct SearchCandidate: Sendable, Hashable {
    public let id: String
    public let title: String
    public let keywords: [String]

    public init(id: String, title: String, keywords: [String] = []) {
        self.id = id
        self.title = title
        self.keywords = keywords
    }
}

public struct RankedCandidate: Sendable {
    public let candidate: SearchCandidate
    public let score: Double
    public let matchedIndices: [Int]
}

/// Tracks how often and how recently each item was launched so frequently
/// used items float to the top ("frecency").
public final class FrecencyStore: @unchecked Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var count: Int
        public var lastUsed: Date
    }

    private var entries: [String: Entry]
    private let url: URL?
    private let lock = NSLock()

    /// - Parameter url: JSON file to persist to; nil keeps it in memory only.
    public init(url: URL?) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    public func recordUse(of id: String, at date: Date = Date()) {
        lock.lock()
        var e = entries[id] ?? Entry(count: 0, lastUsed: date)
        e.count += 1
        e.lastUsed = date
        entries[id] = e
        let snapshot = entries
        lock.unlock()
        persist(snapshot)
    }

    /// A boost in roughly [0, 12]. Uses log(count) so heavy use saturates,
    /// and halves every 7 days since last use.
    public func boost(for id: String, now: Date = Date()) -> Double {
        lock.lock(); defer { lock.unlock() }
        guard let e = entries[id] else { return 0 }
        let days = max(0, now.timeIntervalSince(e.lastUsed) / 86_400)
        let decay = pow(0.5, days / 7)
        return log2(Double(e.count) + 1) * 3 * decay
    }

    public func mostUsed(limit: Int, now: Date = Date()) -> [String] {
        lock.lock()
        let keys = Array(entries.keys)
        lock.unlock()
        return keys
            .map { ($0, boost(for: $0, now: now)) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    private func persist(_ snapshot: [String: Entry]) {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        } catch {
            // Non-fatal: ranking simply won't persist.
        }
    }
}

public enum Ranker {
    /// Fuzzy-filters and orders candidates for `query`, blending match
    /// quality with usage history.
    public static func rank(_ candidates: [SearchCandidate], query: String, frecency: FrecencyStore?, limit: Int = 50) -> [RankedCandidate] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var ranked: [RankedCandidate] = []
        ranked.reserveCapacity(candidates.count)
        for c in candidates {
            guard let m = FuzzyMatcher.bestMatch(q, title: c.title, keywords: c.keywords) else { continue }
            let boost = frecency?.boost(for: c.id) ?? 0
            ranked.append(RankedCandidate(candidate: c, score: m.score + boost, matchedIndices: m.matchedIndices))
        }
        ranked.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.candidate.title.localizedCaseInsensitiveCompare($1.candidate.title) == .orderedAscending
        }
        return Array(ranked.prefix(limit))
    }
}
