import Foundation

/// The result of matching a query against a candidate string.
public struct FuzzyMatch: Equatable, Sendable {
    /// Higher is better. Only comparable between matches of the same query.
    public let score: Double
    /// Character offsets (in `Character` units) of the candidate that matched.
    public let matchedIndices: [Int]
}

/// Subsequence fuzzy matcher with bonuses for word starts, consecutive runs,
/// prefixes and exact matches. Uses dynamic programming to find the
/// best-scoring alignment rather than the first greedy one.
public enum FuzzyMatcher {
    static let baseMatch = 1.0
    static let firstCharBonus = 8.0
    static let wordStartBonus = 6.0
    static let camelBonus = 4.0
    static let consecutiveBonus = 5.0
    static let gapPenalty = 0.4
    static let maxGapPenalty = 3.0

    public static func match(_ query: String, in candidate: String) -> FuzzyMatch? {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        let original = Array(candidate)
        let c = Array(candidate.lowercased())
        guard !q.isEmpty else { return FuzzyMatch(score: 0, matchedIndices: []) }
        // `lowercased()` can change length for some scripts; fall back to a
        // safe comparison in that case.
        guard c.count == original.count, q.count <= c.count else {
            return candidate.lowercased().contains(query.lowercased())
                ? FuzzyMatch(score: 1, matchedIndices: []) : nil
        }

        let m = q.count, n = c.count
        let negInf = -Double.infinity
        var score = Array(repeating: Array(repeating: negInf, count: n), count: m)
        var parent = Array(repeating: Array(repeating: -1, count: n), count: m)

        func positionBonus(_ j: Int) -> Double {
            if j == 0 { return firstCharBonus }
            let prev = original[j - 1], cur = original[j]
            if !prev.isLetter && !prev.isNumber { return wordStartBonus }
            if prev.isLowercase && cur.isUppercase { return camelBonus }
            if !prev.isNumber && cur.isNumber { return camelBonus }
            return 0
        }

        for j in 0..<n where c[j] == q[0] {
            score[0][j] = baseMatch + positionBonus(j) - min(Double(j) * 0.2, 2)
        }
        if m > 1 {
            for i in 1..<m {
                for j in i..<n where c[j] == q[i] {
                    var best = negInf, bestK = -1
                    for k in (i - 1)..<j where score[i - 1][k] > negInf {
                        let gap = j - k - 1
                        let transition = gap == 0
                            ? consecutiveBonus
                            : -min(Double(gap) * gapPenalty, maxGapPenalty)
                        let s = score[i - 1][k] + transition
                        if s > best { best = s; bestK = k }
                    }
                    if bestK >= 0 {
                        score[i][j] = best + baseMatch + positionBonus(j)
                        parent[i][j] = bestK
                    }
                }
            }
        }

        var bestEnd = -1, best = negInf
        for j in 0..<n where score[m - 1][j] > best { best = score[m - 1][j]; bestEnd = j }
        guard bestEnd >= 0 else { return nil }

        var indices = [Int](repeating: 0, count: m)
        var j = bestEnd
        for i in stride(from: m - 1, through: 0, by: -1) {
            indices[i] = j
            j = parent[i][j]
        }

        var total = best
        let lowerQuery = String(q)
        let lowerCandidate = String(c)
        if lowerCandidate == lowerQuery { total += 20 }
        else if lowerCandidate.hasPrefix(lowerQuery) { total += 10 }
        // Prefer shorter candidates when everything else is equal.
        total -= Double(n - m) * 0.05
        return FuzzyMatch(score: total, matchedIndices: indices)
    }

    /// Matches against a title and optional keywords; keyword hits are
    /// slightly discounted relative to title hits.
    public static func bestMatch(_ query: String, title: String, keywords: [String] = []) -> FuzzyMatch? {
        var best = match(query, in: title)
        for keyword in keywords {
            if let m = match(query, in: keyword) {
                let discounted = FuzzyMatch(score: m.score * 0.9, matchedIndices: [])
                if best == nil || discounted.score > best!.score { best = discounted }
            }
        }
        return best
    }
}
