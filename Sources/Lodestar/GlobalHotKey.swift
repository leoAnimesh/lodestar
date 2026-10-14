import Carbon
import LodestarCore

/// Registers a system-wide shortcut with the Carbon Event Manager.
/// RegisterEventHotKey does not require Accessibility permission, unlike a
/// CGEventTap, which is why launchers commonly use it for the main shortcut.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    private static var instances: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1
    private let id: UInt32

    init?(spec: HotkeySpec, action: @escaping () -> Void) {
        self.action = action
        self.id = GlobalHotKey.nextID
        GlobalHotKey.nextID += 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard err == noErr, let target = GlobalHotKey.instances[hkID.id] else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { target.action() }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
        guard status == noErr else { return nil }

        // 'LDST' signature
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C44_5354), id: id)
        let regStatus = RegisterEventHotKey(spec.keyCode, spec.carbonModifiers, hotKeyID,
                                            GetApplicationEventTarget(), 0, &hotKeyRef)
        guard regStatus == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
        GlobalHotKey.instances[id] = self
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        GlobalHotKey.instances[id] = nil
    }
}
