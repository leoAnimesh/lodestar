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

    private var timer: Timer?
    private var watchers = 0
    private var tick = 0

    init() { refresh(includeSlow: true) }

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
    }

    func stopWatching() {
        watchers = max(watchers - 1, 0)
        guard watchers == 0 else { return }
        timer?.invalidate()
        timer = nil
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

    /// Shows the system Accessibility prompt (which also lists Lodestar in
    /// Settings) and opens the pane.
    func requestAccessibility() {
        if !SystemActions.ensureAccessibility(prompt: true) { PermissionsMonitor.open(.accessibility) }
        refresh(includeSlow: false)
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
