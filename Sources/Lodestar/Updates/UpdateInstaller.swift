import AppKit
import LodestarCore

enum UpdateInstallError: Error, CustomStringConvertible {
    case assetMissing(String)
    case missingChecksum(String)
    case checksumMismatch(String)
    case unzipFailed(String)
    case signatureInvalid(String)
    case publisherMismatch
    case staging(String)

    var description: String {
        switch self {
        case .assetMissing(let name):
            return "\(name) couldn't be downloaded from the release (not found), so nothing was changed."
        case .missingChecksum(let name):
            return "The release's SHA256SUMS.txt doesn't list \(name), so the download can't be verified and was not used."
        case .checksumMismatch(let name):
            return "\(name) didn't match its published checksum, so it was not used. Nothing was changed."
        case .unzipFailed(let reason): return "The download couldn't be unpacked: \(reason)"
        case .signatureInvalid(let reason): return "The downloaded app's code signature is invalid: \(reason)"
        case .publisherMismatch: return "The downloaded app isn't signed by the same developer as this copy, so it was not installed."
        case .staging(let reason): return "The update couldn't be prepared: \(reason)"
        }
    }
}

/// One install attempt: download → verify → unpack → validate → swap.
/// Everything before the swap happens in a scratch folder on the app's own
/// volume; the installed app is touched only by `AppReplacer.replace`.
struct UpdateInstaller {
    enum Step {
        case downloading(Int64, Int64?)
        case verifying
        case installing
    }

    let appURL: URL
    let bundleIdentifier: String
    let policy: UpdateHostPolicy
    let appVersion: String
    let replacer: AppReplacer

    func run(_ release: GitHubRelease, progress: @escaping (Step) -> Void) async throws {
        guard let archive = release.appArchive, let sums = release.checksums else {
            throw UpdateInstallError.staging("the release has no app archive or checksum file")
        }
        let fm = FileManager.default
        // Same volume as the app, so the final moves are renames.
        let work: URL
        do {
            work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appURL, create: true)
        } catch {
            work = fm.temporaryDirectory.appendingPathComponent("lodestar-update-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
        }
        var swapped = false
        defer {
            // After a swap the folder holds only the old app's backup, which
            // was already trashed (or is left for the system to clean).
            if !swapped { try? fm.removeItem(at: work) }
        }

        let network = UpdateNetwork(policy: policy, appVersion: appVersion)
        defer { network.invalidate() }

        // 1. The checksum list first: without it there is nothing to verify against.
        let sumsResponse: UpdateNetwork.Response
        do {
            sumsResponse = try await network.fetch(sums.downloadURL, accept: "application/octet-stream", limit: 64 << 10)
        } catch UpdateNetworkError.noRelease {
            throw UpdateInstallError.assetMissing(sums.name)
        }
        let list = ChecksumList(String(decoding: sumsResponse.data, as: UTF8.self))
        guard let expected = list.digest(for: archive.name) else { throw UpdateInstallError.missingChecksum(archive.name) }
        try Task.checkCancellation()

        // 2. The archive, with progress.
        let zip = work.appendingPathComponent(archive.name)
        do {
            _ = try await network.download(archive.downloadURL, to: zip) { received, total in
                progress(.downloading(received, total ?? (archive.size > 0 ? archive.size : nil)))
            }
        } catch UpdateNetworkError.noRelease {
            throw UpdateInstallError.assetMissing(archive.name)
        }
        try Task.checkCancellation()

        // 3. Integrity.
        progress(.verifying)
        guard try SHA256File.hexDigest(of: zip) == expected else { throw UpdateInstallError.checksumMismatch(archive.name) }

        // 4. Unpack and validate.
        let extracted = work.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        let unzip = try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])
        guard unzip.status == 0 else { throw UpdateInstallError.unzipFailed(unzip.output) }
        let newApp = try replacer.findApp(in: extracted)
        try replacer.validate(app: newApp, bundleIdentifier: bundleIdentifier, version: release.version)
        let verify = try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
        guard verify.status == 0 else { throw UpdateInstallError.signatureInvalid(verify.output) }
        // A Developer ID copy only accepts updates from the same team. Ad-hoc
        // copies (local builds, unsigned releases) can't check authorship;
        // the SHA-256 from the same release proves integrity only.
        if let team = Self.teamIdentifier(of: appURL), Self.teamIdentifier(of: newApp) != team {
            throw UpdateInstallError.publisherMismatch
        }
        // Downloaded by URLSession, so normally not quarantined; make sure.
        _ = try? Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
        try Task.checkCancellation()

        // 5. Swap. From here on, no cancellation.
        progress(.installing)
        let backup = try replacer.replace(currentApp: appURL, with: newApp, backupDirectory: work.appendingPathComponent("backup"))
        swapped = true
        // The old version goes to the Trash so it can be recovered by hand.
        if (try? fm.trashItem(at: backup, resultingItemURL: nil)) == nil {
            try? fm.removeItem(at: backup)
        }
        try? fm.removeItem(at: work)
    }

    static func teamIdentifier(of app: URL) -> String? {
        guard let result = try? run("/usr/bin/codesign", ["-dv", "--verbose=2", app.path]) else { return nil }
        for line in result.output.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
            let value = line.dropFirst("TeamIdentifier=".count).trimmingCharacters(in: .whitespaces)
            return value == "not set" || value.isEmpty ? nil : value
        }
        return nil
    }

    /// Runs a tool and returns its exit status with stdout+stderr.
    static func run(_ tool: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw UpdateInstallError.staging("\((tool as NSString).lastPathComponent) couldn't start: \(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
