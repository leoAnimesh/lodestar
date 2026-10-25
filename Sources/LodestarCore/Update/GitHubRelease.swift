import Foundation

/// One file attached to a GitHub release.
public struct ReleaseAsset: Equatable, Sendable {
    public let name: String
    public let downloadURL: URL
    public let size: Int64

    public init(name: String, downloadURL: URL, size: Int64) {
        self.name = name
        self.downloadURL = downloadURL
        self.size = size
    }
}

/// A release as read from the GitHub REST API (`/releases/latest` or `/releases`).
public struct GitHubRelease: Equatable, Sendable {
    public let tagName: String
    public let version: SemanticVersion
    public let name: String
    /// Release notes in Markdown.
    public let notes: String
    public let htmlURL: URL
    public let publishedAt: Date?
    public let isDraft: Bool
    public let isPrerelease: Bool
    public let assets: [ReleaseAsset]

    public init(tagName: String, version: SemanticVersion, name: String, notes: String, htmlURL: URL,
                publishedAt: Date?, isDraft: Bool, isPrerelease: Bool, assets: [ReleaseAsset]) {
        self.tagName = tagName
        self.version = version
        self.name = name
        self.notes = notes
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
        self.assets = assets
    }

    public static let checksumsAssetName = "SHA256SUMS.txt"

    /// The app archive: `Lodestar-<version>.zip` (the name the release workflow
    /// gives it). Falls back to the only `Lodestar-*.zip` if the name differs
    /// slightly (e.g. a `v` in it); never guesses between several.
    public var appArchive: ReleaseAsset? {
        let exact = ["Lodestar-\(version.description).zip", "Lodestar-\(tagName).zip"]
        if let hit = assets.first(where: { exact.contains($0.name) }) { return hit }
        let candidates = assets.filter {
            $0.name.hasPrefix("Lodestar-") && $0.name.lowercased().hasSuffix(".zip")
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    public var checksums: ReleaseAsset? {
        assets.first { $0.name == Self.checksumsAssetName }
            ?? assets.first { $0.name.lowercased() == "checksums.txt" }
    }

    /// In-place install needs both the archive and the checksum list.
    public var isInstallable: Bool { appArchive != nil && checksums != nil }
}

public enum ReleaseParseError: Error, Equatable, CustomStringConvertible {
    case invalidJSON
    case notAVersion(String)

    public var description: String {
        switch self {
        case .invalidJSON: return "The release information from GitHub could not be read."
        case .notAVersion(let tag): return "The release tag “\(tag)” is not a version number."
        }
    }
}

public enum GitHubReleaseParser {
    public static let fallbackPage = URL(string: "https://github.com/leoAnimesh/lodestar/releases")!

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
            let size: Int64?
        }
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: String?
        let published_at: String?
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]?
    }

    /// Parses one release object (the `/releases/latest` response).
    public static func parseRelease(_ data: Data) throws -> GitHubRelease {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { throw ReleaseParseError.invalidJSON }
        return try convert(payload)
    }

    /// Parses a release list (the `/releases` response). Entries whose tag
    /// isn't a version are skipped rather than failing the whole list.
    public static func parseReleaseList(_ data: Data) throws -> [GitHubRelease] {
        guard let payloads = try? JSONDecoder().decode([Payload].self, from: data) else { throw ReleaseParseError.invalidJSON }
        return payloads.compactMap { try? convert($0) }
    }

    private static func convert(_ p: Payload) throws -> GitHubRelease {
        guard let version = SemanticVersion(p.tag_name) else { throw ReleaseParseError.notAVersion(p.tag_name) }
        let assets = (p.assets ?? []).compactMap { a -> ReleaseAsset? in
            guard let url = URL(string: a.browser_download_url) else { return nil }
            return ReleaseAsset(name: a.name, downloadURL: url, size: max(a.size ?? 0, 0))
        }
        let html = p.html_url.flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil } ?? fallbackPage
        let date = p.published_at.flatMap { ISO8601DateFormatter().date(from: $0) }
        return GitHubRelease(tagName: p.tag_name, version: version, name: p.name ?? "Lodestar \(version)",
                             notes: p.body ?? "", htmlURL: html, publishedAt: date, isDraft: p.draft ?? false,
                             isPrerelease: (p.prerelease ?? false) || version.isPrerelease, assets: assets)
    }

    /// The newest release worth offering: never drafts, pre-releases only when
    /// asked for.
    public static func newest(in releases: [GitHubRelease], includePrereleases: Bool) -> GitHubRelease? {
        releases
            .filter { !$0.isDraft && (includePrereleases || !$0.isPrerelease) }
            .max { $0.version < $1.version }
    }
}

/// What a check concluded.
public enum UpdateAvailability: Equatable, Sendable {
    case upToDate
    case available(GitHubRelease)
    /// Newer, but the user chose "Skip This Version" for it. A manual check
    /// still shows it.
    case skipped(GitHubRelease)
}

public enum UpdateDecision {
    public static func evaluate(current: SemanticVersion, candidate: GitHubRelease?, skippedVersion: String?,
                                userInitiated: Bool) -> UpdateAvailability {
        guard let candidate, !candidate.isDraft, candidate.version > current else { return .upToDate }
        if !userInitiated, let skipped = skippedVersion.flatMap(SemanticVersion.init), skipped == candidate.version {
            return .skipped(candidate)
        }
        return .available(candidate)
    }

    /// Whether an automatic check is due.
    public static func isCheckDue(lastCheck: Date?, now: Date, interval: TimeInterval = 24 * 60 * 60) -> Bool {
        guard let lastCheck else { return true }
        // A clock that moved backwards shouldn't stop checks for days.
        if lastCheck > now { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }
}
