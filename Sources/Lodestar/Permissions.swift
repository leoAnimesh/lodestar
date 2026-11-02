import AppKit
import ApplicationServices
import Carbon

/// Live status of the macOS permissions Lodestar can use. Polls while at
/// least one view is watching (onboarding's permissions step, Settings), so
/// a grant in System Settings shows up within a second without a restart.
/// Nothing here changes a permission; the request methods only open the
/// system prompt or the right System Settings pane for the user to decide.
final class PermissionsMonitor: ObservableObject {
    enum Status: Equatable {
        case granted, denied, notDetermined, unknown

        var label: String {
            switch self {
            case .granted: return "Granted"
            case .denied: return "Not Granted"
            case .notDetermined: return "Not Requested"
            case .unknown: return "Unknown"
            }
        }
    }

    @Published private(set) var accessibility: Status = .unknown
    @Published private(set) var automation: Status = .unknown
    @Published private(set) var fullDiskAccess: Status = .unknown
    /// Lodestar has asked for Accessibility before, so it's already listed in
    /// System Settings and the next request can open the pane directly.
    @Published private(set) var accessibilityRequested: Bool

    private static let accessibilityRequestedKey = "permissions.accessibilityRequested"
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var watchers = 0
    private var tick = 0

    init() {
        accessibilityRequested = UserDefaults.standard.bool(forKey: PermissionsMonitor.accessibilityRequestedKey)
        refresh(includeSlow: true)
    }

    /// Required (non-optional) permissions that are granted, for summaries.
    var requiredGrantedCount: Int { [accessibility, automation].filter { $0 == .granted }.count }
    let requiredCount = 2

    func startWatching() {
        watchers += 1
        refresh(includeSlow: true)
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick += 1
            // AX is cheap; the Apple Events and file checks run every few seconds.
            self.refresh(includeSlow: self.tick % 3 == 0)
        }
        // Coming back from System Settings: update right away, not on the next tick.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh(includeSlow: true)
        }
    }

    func stopWatching() {
        watchers = max(watchers - 1, 0)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
    }

    func refresh(includeSlow: Bool = true) {
        let ax: Status = AXIsProcessTrusted() ? .granted : .denied
        if ax != accessibility { accessibility = ax }
        guard includeSlow else { return }
        DispatchQueue.global(qos: .utility).async {
            let auto = PermissionsMonitor.automationStatus()
            let fda = PermissionsMonitor.fullDiskAccessStatus()
            DispatchQueue.main.async {
                if auto != self.automation { self.automation = auto }
                if fda != self.fullDiskAccess { self.fullDiskAccess = fda }
            }
        }
    }

    // MARK: Checks

    /// Apple Events consent for System Events, which the system commands
    /// (sleep, lock, dark mode...) talk to. Never prompts.
    static func automationStatus() -> Status {
        let bundleID = "com.apple.systemevents"
        var target = AEAddressDesc()
        let status: OSStatus = bundleID.withCString { ptr in
            guard AECreateDesc(DescType(typeApplicationBundleID), ptr, strlen(ptr), &target) == noErr else { return -1 }
            defer { AEDisposeDesc(&target) }
            return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
        }
        switch Int(status) {
        case Int(noErr): return .granted
        case -1743: return .denied            // errAEEventNotPermitted
        case -1744: return .notDetermined     // errAEEventWouldRequireUserConsent
        case -600: return .notDetermined      // procNotFound: System Events isn't running yet
        default: return .unknown
        }
    }

    /// There's no API for Full Disk Access; reading a location that only
    /// FDA unlocks is the standard probe. Only metadata is touched.
    static func fullDiskAccessStatus() -> Status {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let probes = [home + "/Library/Safari", home + "/Library/Mail", "/Library/Application Support/com.apple.TCC"]
        for path in probes where FileManager.default.fileExists(atPath: path) {
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: path)
                return .granted
            } catch {
                return .denied
            }
        }
        return .unknown
    }

    // MARK: Opening System Settings (the user decides there)

    enum Pane: String {
        case accessibility = "Privacy_Accessibility"
        case automation = "Privacy_Automation"
        case fullDiskAccess = "Privacy_AllFiles"
    }

    /// What System Settings calls the Accessibility list on this macOS
    /// ("Device Control and Data Access" from macOS 27).
    static var accessibilityPaneName: String {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? "Device Control and Data Access" : "Accessibility"
    }

    static func open(_ pane: Pane) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openKeyboardShortcuts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The first time, shows the system Accessibility prompt: it adds
    /// Lodestar to the list in System Settings and its button opens the pane.
    /// After that the prompt adds nothing, so go straight to the pane.
    func requestAccessibility() {
        if accessibilityRequested {
            PermissionsMonitor.open(.accessibility)
        } else {
            markAccessibilityRequested()
            SystemActions.ensureAccessibility(prompt: true)
        }
        refresh(includeSlow: false)
    }

    private func markAccessibilityRequested() {
        accessibilityRequested = true
        UserDefaults.standard.set(true, forKey: PermissionsMonitor.accessibilityRequestedKey)
    }

    /// Asks macOS to show its Automation consent prompt for System Events.
    func requestAutomation() {
        DispatchQueue.global(qos: .userInitiated).async {
            let url = URL(fileURLWithPath: "/System/Library/CoreServices/System Events.app")
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            let group = DispatchGroup()
            group.enter()
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in group.leave() }
            _ = group.wait(timeout: .now() + 3)
            var target = AEAddressDesc()
            let bundleID = "com.apple.systemevents"
            let status: OSStatus = bundleID.withCString { ptr in
                guard AECreateDesc(DescType(typeApplicationBundleID), ptr, strlen(ptr), &target) == noErr else { return -1 }
                defer { AEDisposeDesc(&target) }
                return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), true)
            }
            DispatchQueue.main.async {
                if status == -1743 { PermissionsMonitor.open(.automation) }
                self.refresh()
            }
        }
    }
}
