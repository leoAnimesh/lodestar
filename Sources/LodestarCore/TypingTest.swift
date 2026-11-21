import Foundation

/// Scoring for the typing test: a target text vs. what has been typed.
public struct TypingTest {
    public let target: [Character]

    public init(_ target: String) { self.target = Array(target) }

    public enum CharState: Equatable { case correct, wrong, pending }

    public func states(typed: String) -> [CharState] {
        let t = Array(typed)
        return target.indices.map { i in
            i >= t.count ? .pending : t[i] == target[i] ? .correct : .wrong
        }
    }

    public func isDone(typed: String) -> Bool { typed.count >= target.count }

    /// Words per minute (5 characters = 1 word), counting correct characters only.
    public func wpm(typed: String, elapsed: TimeInterval) -> Int {
        guard elapsed > 0 else { return 0 }
        let correct = states(typed: typed).filter { $0 == .correct }.count
        return Int((Double(correct) / 5) / (elapsed / 60))
    }

    /// Percentage of typed characters (within the target) that are correct.
    public func accuracy(typed: String) -> Int {
        let s = states(typed: typed)
        let typedCount = s.filter { $0 != .pending }.count
        guard typedCount > 0 else { return 100 }
        return s.filter { $0 == .correct }.count * 100 / typedCount
    }

    public static func randomText(words count: Int = 25) -> String {
        (0..<count).map { _ in words.randomElement()! }.joined(separator: " ")
    }

    static let words = """
    the be to of and a in that have it for not on with he as you do at this but his by from they we say her she or \
    an will my one all would there their what so up out if about who get which go me when make can like time no just \
    him know take people into year your good some could them see other than then now look only come its over think \
    also back after use two how our work first well way even new want because any these give day most us great \
    between need large often hand high place hold turn small number off always move live point under last never \
    city tree cross farm hard start might story saw far sea draw left late run while press close night real life few
    """.split(whereSeparator: \.isWhitespace).map(String.init)
}
