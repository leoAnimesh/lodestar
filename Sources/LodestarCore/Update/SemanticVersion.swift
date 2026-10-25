import Foundation

/// A release version such as `1.2.3`, `v0.4.0` or `1.0.0-beta.2`.
///
/// Ordering follows Semantic Versioning 2.0: major, minor and patch compare
/// numerically; a pre-release sorts below the plain release with the same
/// numbers (`1.0.0-beta < 1.0.0`); pre-release identifiers compare one by one,
/// numeric identifiers numerically and below alphanumeric ones
/// (`alpha < alpha.1 < beta < beta.2 < beta.11 < rc.1`). Build metadata
/// (`+abc`) is accepted and ignored, as the spec says.
public struct SemanticVersion: Hashable, Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// Dot-separated identifiers after `-`; empty for a normal release.
    public let prerelease: [String]

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Parses `X.Y.Z`, with an optional `v`/`V` prefix, `-pre.release` suffix
    /// and `+build` metadata. Two-part versions (`1.2`) are accepted as `1.2.0`
    /// because tags are sometimes written that way. Returns nil for anything else.
    public init?(_ text: String) {
        var body = Substring(text.trimmingCharacters(in: .whitespaces))
        if body.first == "v" || body.first == "V" { body = body.dropFirst() }
        if let plus = body.firstIndex(of: "+") { body = body[..<plus] }
        var pre: [String] = []
        if let dash = body.firstIndex(of: "-") {
            let suffix = body[body.index(after: dash)...]
            let parts = suffix.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard !parts.isEmpty, parts.allSatisfy({ part in
                !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
            }) else { return nil }
            pre = parts
            body = body[..<dash]
        }
        let numbers = body.split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 2 || numbers.count == 3 else { return nil }
        var values: [Int] = []
        for n in numbers {
            guard !n.isEmpty, n.count <= 9, n.allSatisfy({ $0.isASCII && $0.isNumber }), let v = Int(n) else { return nil }
            values.append(v)
        }
        if values.count == 2 { values.append(0) }
        self.init(major: values[0], minor: values[1], patch: values[2], prerelease: pre)
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    /// `X.Y.Z` without any suffix.
    public var core: String { "\(major).\(minor).\(patch)" }

    public var description: String { isPrerelease ? "\(core)-\(prerelease.joined(separator: "."))" : core }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.isPrerelease, rhs.isPrerelease) {
        case (false, false), (false, true): return false
        case (true, false): return true
        case (true, true): break
        }
        for (a, b) in zip(lhs.prerelease, rhs.prerelease) where a != b {
            switch (Int(a), Int(b)) {
            case let (x?, y?): return x < y
            case (.some, nil): return true    // numeric < alphanumeric
            case (nil, .some): return false
            case (nil, nil): return a < b
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    /// Equality ignores nothing but build metadata (already dropped while parsing).
    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch && lhs.prerelease == rhs.prerelease
    }
}
