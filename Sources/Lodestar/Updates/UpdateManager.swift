import AppKit
import LodestarCore

/// Checks GitHub Releases for a newer Lodestar and installs it in place.
///
/// Check: `GET api.github.com/repos/leoAnimesh/lodestar/releases/latest`
/// (or `/releases` with pre-releases on), unauthenticated, with a
/// `User-Agent` and `If-None-Match` so unchanged answers are cheap 304s.
/// Runs ~20 s after launch and then whenever 24 h have passed (re-evaluated
/// hourly, so a sleeping Mac catches up), plus on demand.
///
/// Install: download the release's `Lodestar-<version>.zip` and
/// `SHA256SUMS.txt`, require the zip's SHA-256 to match (fail closed), unzip
/// with `ditto`, require the same bundle ID, the expected version and a valid
/// code signature (and the same Developer ID team when this copy has one),
/// then swap the bundles with `AppReplacer` (old one to the Trash) and
/// relaunch through a detached shell that waits for this process to exit.
/// If Lodestar can't replace itself where it is, it offers the release page.
///
/// Developer aids (never active in normal use): `LODESTAR_UPDATE_URL` points
/// the check at another feed and allows loopback HTTP, for testing against a
/// local server; with it set, `LODESTAR_UPDATE_AUTOINSTALL=1` installs a found
/// update without asking.
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(GitHubRelease)
        case downloading(received: Int64, total: Int64?)
        case verifying
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// The release the window is about (kept while downloading/failing).
    @Published private(set) var release: GitHubRelease?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastError: String?
    @Published var automaticallyChecks: Bool {
        didSet { defaults.set(automaticallyChecks, forKey: Keys.autoCheck); reschedule() }
    }
    @Published var includePrereleases: Bool {
        didSet {
            defaults.set(includePrereleases, forKey: Keys.prereleases)
            // A different endpoint: the cached ETag doesn't apply.
            defaults.removeObject(forKey: Keys.etag)
        }
    }

    let currentVersionText: String
    let currentVersion: SemanticVersion?
    /// Why this copy can't replace itself (nil when it can).
    var installBlocker: String? { replacer.installProblem(for: Bundle.main.bundleURL)?.description }

    var onShowWindow: (() -> Void)?

    private enum Keys {
        static let autoCheck = "updates.automaticallyCheck"
        static let prereleases = "updates.includePrereleases"
        static let lastCheck = "updates.lastCheck"
        static let skipped = "updates.skippedVersion"
        static let etag = "updates.etag"
        static let etagURL = "updates.etagURL"
        static let cachedBody = "updates.cachedResponse"
        static let updatedFrom = "updates.updatedFrom"
    }

    private let defaults: UserDefaults
    private let environment: [String: String]
    private let replacer = AppReplacer()
    private var timer: Timer?
    private var work: Task<Void, Never>?
    private var started = false

    init(defaults: UserDefaults = .standard, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.defaults = defaults
        self.environment = environment
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        currentVersionText = short ?? "development build"
        currentVersion = short.flatMap(SemanticVersion.init)
        automaticallyChecks = defaults.object(forKey: Keys.autoCheck) as? Bool ?? true
        includePrereleases = defaults.bool(forKey: Keys.prereleases)
        lastChecked = defaults.object(forKey: Keys.lastCheck) as? Date
    }

    private var feed: UpdateFeed { UpdateFeed.resolve(environment: environment, includePrereleases: includePrereleases) }
    private var isDeveloperFeed: Bool { environment[UpdateFeed.overrideVariable]?.isEmpty == false }

    // MARK: Lifecycle

    /// Call once at launch.
    func start(checkNow: Bool = false) {
        guard !started else { return }
        started = true
        announceCompletedUpdate()
        if checkNow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.checkForUpdates(userInitiated: true) }
        }
        reschedule(initialDelay: checkNow ? nil : 20)
    }

    private func reschedule(initialDelay: TimeInterval? = nil) {
        timer?.invalidate()
        timer = nil
        guard started, automaticallyChecks, currentVersion != nil else { return }
        if let initialDelay {
            DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { [weak self] in self?.automaticCheckIfDue() }
        }
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in self?.automaticCheckIfDue() }
        timer.tolerance = 5 * 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func automaticCheckIfDue() {
        guard automaticallyChecks, UpdateDecision.isCheckDue(lastCheck: lastChecked, now: Date()) else { return }
        checkForUpdates(userInitiated: false)
    }

    /// After a relaunch into a new version, say so once.
    private func announceCompletedUpdate() {
        guard let from = defaults.string(forKey: Keys.updatedFrom) else { return }
        defaults.removeObject(forKey: Keys.updatedFrom)
        if from != currentVersionText {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [currentVersionText] in
                HUD.show("Updated to Lodestar \(currentVersionText)", symbol: "checkmark.seal")
            }
        }
    }

    // MARK: Check

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .verifying, .installing: return true
        default: return false
        }
    }

    /// `userInitiated` shows the window with whatever the check finds;
    /// automatic checks only show it for a new, non-skipped version.
    func checkForUpdates(userInitiated: Bool) {
        guard !isBusy else { if userInitiated { onShowWindow?() }; return }
        guard let current = currentVersion else {
            if userInitiated {
                phase = .failed("This is a development build without a version number, so it can't check for updates. Build the app with ./scripts/bundle.sh.")
                onShowWindow?()
            }
            return
        }
        phase = .checking
        release = nil
        if userInitiated { onShowWindow?() }
        let feed = self.feed
        let prereleases = includePrereleases
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let candidate = try await self.fetchNewest(feed: feed, includePrereleases: prereleases)
                await MainActor.run {
                    self.recordCheck(error: nil)
                    let decision = UpdateDecision.evaluate(current: current, candidate: candidate,
                                                           skippedVersion: self.defaults.string(forKey: Keys.skipped),
                                                           userInitiated: userInitiated)
                    switch decision {
                    case .available(let release):
                        self.release = release
                        self.phase = .available(release)
                        if self.isDeveloperFeed, self.environment["LODESTAR_UPDATE_AUTOINSTALL"] == "1" {
                            self.installUpdate()
                        } else {
                            self.onShowWindow?()
                        }
                    case .upToDate, .skipped:
                        self.phase = userInitiated ? .upToDate : .idle
                    }
                }
            } catch {
                let message = Self.message(for: error)
                NSLog("Lodestar: update check failed: \(message)")
                await MainActor.run {
                    self.recordCheck(error: message)
                    self.phase = userInitiated ? .failed(message) : .idle
                }
            }
        }
    }

    private func recordCheck(error: String?) {
        lastError = error
        if error == nil {
            lastChecked = Date()
            defaults.set(lastChecked, forKey: Keys.lastCheck)
        }
    }

    private func fetchNewest(feed: UpdateFeed, includePrereleases: Bool) async throws -> GitHubRelease? {
        let network = UpdateNetwork(policy: feed.policy, appVersion: currentVersionText)
        defer { network.invalidate() }
        let sameURL = defaults.string(forKey: Keys.etagURL) == feed.url.absoluteString
        let cached = sameURL ? defaults.data(forKey: Keys.cachedBody) : nil
        let etag = cached != nil ? defaults.string(forKey: Keys.etag) : nil
        let response = try await network.fetch(feed.url, etag: etag)
        let body: Data
        if response.status == 304, let cached {
            body = cached
        } else {
            body = response.data
            if let tag = response.etag, body.count < 512 << 10 {
                defaults.set(tag, forKey: Keys.etag)
                defaults.set(feed.url.absoluteString, forKey: Keys.etagURL)
                defaults.set(body, forKey: Keys.cachedBody)
            } else {
                defaults.removeObject(forKey: Keys.etag)
                defaults.removeObject(forKey: Keys.cachedBody)
            }
        }
        do {
            return try UpdateFeed.parse(body, includePrereleases: includePrereleases)
        } catch {
            // A corrupt cache must not wedge future checks.
            defaults.removeObject(forKey: Keys.etag)
            throw error
        }
    }

    /// Our own errors carry a plain-language description; system errors use
    /// their localized description (an NSError's `description` is a dump).
    static func message(for error: Error) -> String {
        switch error {
        case let e as UpdateNetworkError: return e.description
        case let e as UpdateInstallError: return e.description
        case let e as ReleaseParseError: return e.description
        case let e as BundleValidationError: return e.description
        case let e as ReplaceError: return e.description
        case let e as InstallProblem: return e.description
        default: return error.localizedDescription
        }
    }

    /// For the snapshot tour: show the window in a given state with a sample
    /// release, without any network access.
    func presentSample(_ phase: Phase, release: GitHubRelease?) {
        self.release = release
        self.phase = phase
        onShowWindow?()
    }

    // MARK: User choices

    func skipThisVersion() {
        guard let release else { return }
        defaults.set(release.version.description, forKey: Keys.skipped)
        phase = .idle
    }

    func later() {
        work?.cancel()
        if !isBusy || phase == .checking { phase = .idle }
    }

    func cancelDownload() {
        work?.cancel()
    }

    func openReleasePage() {
        NSWorkspace.shared.open(release?.htmlURL ?? UpdateFeed.releasesPage)
    }

    // MARK: Install

    func installUpdate() {
        guard let release, !isBusy else { return }
        if let blocker = installBlocker {
            phase = .failed(blocker + " You can download the new version from the release page.")
            return
        }
        guard release.isInstallable, release.appArchive != nil, release.checksums != nil else {
            phase = .failed("This release has no app archive and checksum file to install from. Download it from the release page instead.")
            return
        }
        let appURL = Bundle.main.bundleURL
        let bundleID = Bundle.main.bundleIdentifier ?? "io.github.lodestar-launcher"
        let policy = feed.policy
        phase = .downloading(received: 0, total: release.appArchive?.size)
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let installer = UpdateInstaller(appURL: appURL, bundleIdentifier: bundleID, policy: policy,
                                                appVersion: self.currentVersionText, replacer: self.replacer)
                try await installer.run(release) { [weak self] step in
                    DispatchQueue.main.async {
                        guard let self, self.isBusy else { return }
                        switch step {
                        case .downloading(let received, let total): self.phase = .downloading(received: received, total: total)
                        case .verifying: self.phase = .verifying
                        case .installing: self.phase = .installing
                        }
                    }
                }
                NSLog("Lodestar: installed \(release.version); relaunching")
                await MainActor.run {
                    self.defaults.set(self.currentVersionText, forKey: Keys.updatedFrom)
                    self.defaults.removeObject(forKey: Keys.skipped)
                    AppRelauncher.relaunch(appURL)
                }
            } catch is CancellationError {
                await MainActor.run { self.phase = .available(release) }
            } catch {
                let message = Self.message(for: error)
                NSLog("Lodestar: update to \(release.version) failed: \(message)")
                await MainActor.run { self.phase = .failed(message) }
            }
        }
    }
}

/// Starts a detached shell that waits (up to ~10 s) for this process to exit,
/// then opens the app at `appURL` again; then quits. Path and PID are passed
/// as arguments, never spliced into the script.
enum AppRelauncher {
    static func relaunch(_ appURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "i=0; while /bin/kill -0 \"$1\" 2>/dev/null && [ $i -lt 50 ]; do sleep 0.2; i=$((i+1)); done; /usr/bin/open \"$0\"",
            appURL.path, String(ProcessInfo.processInfo.processIdentifier),
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("Lodestar: couldn't start the relauncher: \(error.localizedDescription); please open Lodestar again")
        }
        DispatchQueue.main.async { NSApp.terminate(nil) }
        // Nothing is left to save; don't let a stuck window block the update.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
    }
}
