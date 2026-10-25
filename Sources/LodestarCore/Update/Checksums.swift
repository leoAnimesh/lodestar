import CryptoKit
import Foundation

/// A `SHA256SUMS.txt` file as written by `shasum -a 256 <files>`:
/// one `<64 hex digits><space><space or *><file name>` per line.
public struct ChecksumList: Equatable, Sendable {
    /// File name → lower-case hex digest.
    public let digests: [String: String]
    /// Names listed more than once with different digests; asking for one fails.
    public let conflicting: Set<String>

    public init(_ text: String) {
        var digests: [String: String] = [:]
        var conflicting: Set<String> = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.count > 66 else { continue }
            let hash = String(line.prefix(64)).lowercased()
            guard hash.allSatisfy({ $0.isHexDigit }) else { continue }
            var rest = line.dropFirst(64)
            guard rest.first == " " else { continue }
            rest = rest.dropFirst()
            if rest.first == " " || rest.first == "*" { rest = rest.dropFirst() }
            var name = String(rest)
            // `shasum` run on a path records it; only the file name matters.
            if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
            guard !name.isEmpty else { continue }
            if let existing = digests[name], existing != hash { conflicting.insert(name) }
            digests[name] = hash
        }
        self.digests = digests
        self.conflicting = conflicting
    }

    /// The digest for `name`, or nil when it is missing or ambiguous.
    public func digest(for name: String) -> String? {
        conflicting.contains(name) ? nil : digests[name]
    }
}

public enum SHA256File {
    /// Hex SHA-256 of a file, read in 1 MB chunks.
    public static func hexDigest(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Which URLs the updater may contact. Checked for every request and redirect.
///
/// HTTPS to GitHub's API, website and release-download hosts only. A
/// developer override (`LODESTAR_UPDATE_URL`) additionally allows plain HTTP to
/// this Mac (`127.0.0.1`, `localhost`) so the whole flow can be tested against
/// a local server.
public struct UpdateHostPolicy: Equatable, Sendable {
    public static let githubHosts: Set<String> = [
        "api.github.com", "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com",
    ]

    public let allowsLoopback: Bool

    public init(allowsLoopback: Bool = false) { self.allowsLoopback = allowsLoopback }

    public func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(),
              url.user == nil, url.password == nil else { return false }
        if allowsLoopback, scheme == "http" || scheme == "https", host == "127.0.0.1" || host == "localhost" {
            return true
        }
        guard scheme == "https" else { return false }
        if let port = url.port, port != 443 { return false }
        return Self.githubHosts.contains(host)
    }
}

/// Where the updater reads releases from.
public struct UpdateFeed: Equatable, Sendable {
    public static let overrideVariable = "LODESTAR_UPDATE_URL"
    public static let repository = "leoAnimesh/lodestar"
    public static let latestURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    public static let listURL = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=20")!
    public static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!

    /// The URL to fetch. With pre-releases on, the list endpoint is used,
    /// because `/releases/latest` never returns a pre-release.
    public let url: URL
    /// True when `url` returns a list rather than one release.
    public let isList: Bool
    public let policy: UpdateHostPolicy

    public init(url: URL, isList: Bool, policy: UpdateHostPolicy) {
        self.url = url
        self.isList = isList
        self.policy = policy
    }

    /// The override, if set, is used as-is (it may serve one release or a
    /// list; the response shape decides) and enables loopback hosts.
    public static func resolve(environment: [String: String], includePrereleases: Bool) -> UpdateFeed {
        if let raw = environment[overrideVariable]?.trimmingCharacters(in: .whitespaces), !raw.isEmpty,
           let url = URL(string: raw) {
            return UpdateFeed(url: url, isList: false, policy: UpdateHostPolicy(allowsLoopback: true))
        }
        return includePrereleases
            ? UpdateFeed(url: listURL, isList: true, policy: UpdateHostPolicy())
            : UpdateFeed(url: latestURL, isList: false, policy: UpdateHostPolicy())
    }

    /// Parses either response shape: an object (one release) or an array.
    public static func parse(_ data: Data, includePrereleases: Bool) throws -> GitHubRelease? {
        let trimmed = data.first(where: { !($0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09) })
        if trimmed == UInt8(ascii: "[") {
            return GitHubReleaseParser.newest(in: try GitHubReleaseParser.parseReleaseList(data),
                                              includePrereleases: includePrereleases)
        }
        let release = try GitHubReleaseParser.parseRelease(data)
        return GitHubReleaseParser.newest(in: [release], includePrereleases: includePrereleases)
    }
}
