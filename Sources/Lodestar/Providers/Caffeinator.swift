import AppKit
import IOKit.pwr_mgt
import LodestarCore

/// Keeps the Mac (and its display) awake with an IOKit power assertion,
/// the same mechanism `caffeinate -d` uses, without spawning a process.
/// Timed sessions release themselves; macOS also drops the assertion if
/// Lodestar exits for any reason, so the Mac is never left caffeinated.
final class Caffeinator {
    private(set) var state = CaffeinateState()
    private var assertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private var expiryTimer: Timer?
    private var tickTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    /// Called on the main thread whenever the session starts, ends or its
    /// remaining time changes enough to update visible text (every 30 s).
    var onChange: (() -> Void)?

    static let assertionName = "Lodestar Caffeinate"

    init() {
        // Timers don't fire while the Mac sleeps; re-check expiry on wake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.checkExpiry() }
    }

    deinit {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        releaseAssertion()
        expiryTimer?.invalidate()
        tickTimer?.invalidate()
    }

    var isActive: Bool { state.isActive(at: Date()) }
    var statusText: String? { state.statusText(at: Date()) }
    /// Whether an IOKit assertion is currently held (for tests and diagnostics).
    var holdsAssertion: Bool { assertionID != IOPMAssertionID(kIOPMNullAssertionID) }

    /// Starts a session, replacing any running one. Returns false if macOS
    /// refused the assertion.
    @discardableResult
    func start(_ duration: CaffeinateDuration) -> Bool {
        releaseAssertion()
        var id = IOPMAssertionID(kIOPMNullAssertionID)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Caffeinator.assertionName as CFString,
            &id)
        guard result == kIOReturnSuccess else {
            NSLog("Lodestar: IOPMAssertionCreateWithName failed (\(result))")
            state.stop()
            scheduleTimers()
            onChange?()
            return false
        }
        assertionID = id
        if let seconds = duration.seconds {
            // Belt and braces: macOS releases the assertion itself at the end
            // even if our timer were delayed. Our release later is harmless.
            IOPMAssertionSetProperty(id, kIOPMAssertionTimeoutKey as CFString, NSNumber(value: seconds))
            IOPMAssertionSetProperty(id, kIOPMAssertionTimeoutActionKey as CFString,
                                     kIOPMAssertionTimeoutActionRelease as CFString)
        }
        state.start(duration, at: Date())
        scheduleTimers()
        onChange?()
        return true
    }

    /// Ends the session and releases the assertion. Safe to call any time.
    func stop() {
        let wasActive = state.stop()
        releaseAssertion()
        scheduleTimers()
        if wasActive { onChange?() }
    }

    private func releaseAssertion() {
        guard holdsAssertion else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(kIOPMNullAssertionID)
    }

    private func checkExpiry() {
        if state.expireIfNeeded(at: Date()) {
            releaseAssertion()
            scheduleTimers()
            onChange?()
        }
    }

    private func scheduleTimers() {
        expiryTimer?.invalidate(); expiryTimer = nil
        tickTimer?.invalidate(); tickTimer = nil
        guard let session = state.session else { return }
        if let end = session.endDate {
            let timer = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in self?.checkExpiry() }
            RunLoop.main.add(timer, forMode: .common)
            expiryTimer = timer
            // Keeps "42m left" in the menu and launcher current.
            let tick = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.checkExpiry()
                if self.state.session != nil { self.onChange?() }
            }
            tick.tolerance = 5
            RunLoop.main.add(tick, forMode: .common)
            tickTimer = tick
        }
    }
}
