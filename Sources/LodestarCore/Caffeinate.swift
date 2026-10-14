import Foundation

/// How long a caffeinate session lasts; `seconds == nil` means until stopped.
public struct CaffeinateDuration: Equatable, Hashable, Sendable {
    public let seconds: TimeInterval?

    public init(seconds: TimeInterval?) { self.seconds = seconds }

    public static let indefinitely = CaffeinateDuration(seconds: nil)
    public static let thirtyMinutes = CaffeinateDuration(seconds: 30 * 60)
    public static let oneHour = CaffeinateDuration(seconds: 60 * 60)
    public static let twoHours = CaffeinateDuration(seconds: 2 * 60 * 60)

    /// The variants offered as launcher commands, in display order.
    public static let presets: [CaffeinateDuration] = [.indefinitely, .thirtyMinutes, .oneHour, .twoHours]

    /// "Caffeinate", "Caffeinate for 30 Minutes", "Caffeinate for 1 Hour"…
    public var commandTitle: String {
        guard let seconds else { return "Caffeinate" }
        return "Caffeinate for \(CaffeinateDuration.spelledOut(seconds))"
    }

    /// Stable command ID: "cmd:caffeinate", "cmd:caffeinate-30m", "cmd:caffeinate-1h"…
    public var commandID: String {
        guard let seconds else { return "cmd:caffeinate" }
        let minutes = Int((seconds / 60).rounded())
        return minutes % 60 == 0 ? "cmd:caffeinate-\(minutes / 60)h" : "cmd:caffeinate-\(minutes)m"
    }

    /// "30 Minutes", "1 Hour", "2 Hours", "1 Hour 30 Minutes"
    static func spelledOut(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        let h = minutes / 60, m = minutes % 60
        var parts: [String] = []
        if h > 0 { parts.append(h == 1 ? "1 Hour" : "\(h) Hours") }
        if m > 0 || h == 0 { parts.append(m == 1 ? "1 Minute" : "\(m) Minutes") }
        return parts.joined(separator: " ")
    }
}

/// One running caffeinate session.
public struct CaffeinateSession: Equatable, Sendable {
    public let start: Date
    public let duration: CaffeinateDuration

    public init(start: Date, duration: CaffeinateDuration) {
        self.start = start
        self.duration = duration
    }

    /// When the session ends on its own; nil for an indefinite session.
    public var endDate: Date? { duration.seconds.map { start.addingTimeInterval($0) } }

    /// Seconds left (never negative); nil for an indefinite session.
    public func remaining(at now: Date) -> TimeInterval? {
        endDate.map { max(0, $0.timeIntervalSince(now)) }
    }

    public func isExpired(at now: Date) -> Bool {
        guard let endDate else { return false }
        return now >= endDate
    }
}

/// Whether Lodestar is keeping the Mac awake, and for how long. Pure state:
/// the app pairs it with an IOKit power assertion and a timer.
public struct CaffeinateState: Equatable, Sendable {
    public private(set) var session: CaffeinateSession?

    public init(session: CaffeinateSession? = nil) { self.session = session }

    public func isActive(at now: Date) -> Bool {
        guard let session else { return false }
        return !session.isExpired(at: now)
    }

    /// Starts (or restarts, replacing the current session) a session.
    public mutating func start(_ duration: CaffeinateDuration, at now: Date) {
        session = CaffeinateSession(start: now, duration: duration)
    }

    /// Ends the session. Returns whether one was running.
    @discardableResult
    public mutating func stop() -> Bool {
        defer { session = nil }
        return session != nil
    }

    /// Clears an expired session. Returns true when this call ended it, so
    /// the caller knows to release its assertion.
    @discardableResult
    public mutating func expireIfNeeded(at now: Date) -> Bool {
        guard let session, session.isExpired(at: now) else { return false }
        self.session = nil
        return true
    }

    /// "Active — 42m left", "Active — 1h 5m left", "Active — until stopped", or nil when inactive.
    public func statusText(at now: Date) -> String? {
        guard let session, isActive(at: now) else { return nil }
        guard let remaining = session.remaining(at: now) else { return "Active — until stopped" }
        return "Active — \(CaffeinateState.formatRemaining(remaining)) left"
    }

    /// Short remaining time, rounding minutes up so a fresh 30-minute session
    /// reads "30m" and the last seconds read "1m": "2h", "1h 5m", "42m", "1m".
    public static func formatRemaining(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// Orders launcher results so the relevant command leads: while active,
    /// "Decaffeinate" moves ahead of the caffeinate variants; while inactive
    /// it's dropped. Other IDs keep their positions.
    public static func arrange(_ ids: [String], active: Bool, decaffeinateID: String = "cmd:decaffeinate") -> [String] {
        guard active else { return ids.filter { $0 != decaffeinateID } }
        guard let decafIndex = ids.firstIndex(of: decaffeinateID),
              let firstCaff = ids.firstIndex(where: { isCaffeinateID($0) }),
              firstCaff < decafIndex else { return ids }
        var out = ids
        out.remove(at: decafIndex)
        out.insert(decaffeinateID, at: firstCaff)
        return out
    }

    public static func isCaffeinateID(_ id: String) -> Bool {
        id == "cmd:caffeinate" || id.hasPrefix("cmd:caffeinate-")
    }
}
