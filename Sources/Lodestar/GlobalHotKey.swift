import Carbon
import Foundation
import LodestarCore

enum GlobalHotKeyError: LocalizedError {
    case handlerUnavailable(OSStatus)
    case registrationFailed(HotkeySpec, OSStatus)

    var errorDescription: String? {
        switch self {
        case .handlerUnavailable(let status):
            return "Couldn't install the shortcut handler (error \(status))."
        case .registrationFailed(let spec, let status) where Int(status) == eventHotKeyExistsErr:
            return "\(spec) is already in use. Try a different shortcut."
        case .registrationFailed(let spec, let status):
            return "Couldn't register \(spec) (error \(status)). Try a different shortcut."
        }
    }
}

/// Registers a system-wide shortcut with the Carbon Event Manager.
/// RegisterEventHotKey does not require Accessibility permission, unlike a
/// CGEventTap, which is why launchers commonly use it for the main shortcut.
///
/// The shortcut can be changed at runtime with `register(_:)`, which keeps the
/// previous one if the new combo can't be registered, and temporarily released
/// with `suspend()` (e.g. while a hotkey recorder is capturing).
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private let action: () -> Void

    /// The shortcut that is active (or would be, if not suspended).
    private(set) var spec: HotkeySpec?
    private(set) var isSuspended = false

    private static var instances: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1
    private let id: UInt32

    /// One application-wide handler dispatches to instances by hotkey ID.
    /// Carbon rejects installing the same handler twice (eventHandlerAlreadyInstalledErr),
    /// so it is installed once and kept for the life of the process.
    private static let handlerStatus: OSStatus = {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        return InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard err == noErr, let target = GlobalHotKey.instances[hkID.id] else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { target.action() }
            return noErr
        }, 1, &eventType, nil, nil)
    }()

    init(action: @escaping () -> Void) {
        self.action = action
        self.id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1
        GlobalHotKey.instances[id] = self
    }

    deinit {
        unregisterRef()
        GlobalHotKey.instances[id] = nil
    }

    /// Switches to `newSpec`. If it can't be registered, the previous shortcut
    /// stays registered and the error is thrown.
    func register(_ newSpec: HotkeySpec) throws {
        let handlerStatus = GlobalHotKey.handlerStatus
        guard handlerStatus == noErr else { throw GlobalHotKeyError.handlerUnavailable(handlerStatus) }
        let previous = spec
        unregisterRef()
        let status = registerRef(newSpec)
        guard status == noErr else {
            if let previous, !isSuspended, registerRef(previous) != noErr {
                NSLog("Lodestar: could not restore previous hotkey \(previous)")
            }
            throw GlobalHotKeyError.registrationFailed(newSpec, status)
        }
        spec = newSpec
        if isSuspended { unregisterRef() }
    }

    /// Releases the shortcut so its key combo reaches the app as a normal key event.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        unregisterRef()
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        guard let spec, hotKeyRef == nil else { return }
        let status = registerRef(spec)
        if status != noErr { NSLog("Lodestar: could not re-register \(spec) (error \(status))") }
    }

    private func registerRef(_ spec: HotkeySpec) -> OSStatus {
        // 'LDST' signature
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C44_5354), id: id)
        return RegisterEventHotKey(spec.keyCode, spec.carbonModifiers, hotKeyID,
                                   GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func unregisterRef() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}
