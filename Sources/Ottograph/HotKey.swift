import Carbon.HIToolbox
import Foundation

/// Minimal Carbon global hot key wrapper (works from menu bar apps without
/// any extra permissions). Each instance gets a unique hot key ID and its
/// handler ignores events for other hot keys, so multiple instances can
/// coexist. Deallocate the instance to unregister.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void
    private let hotKeyID: EventHotKeyID

    private static var nextID: UInt32 = 1

    init?(keyCode: UInt32, carbonModifiers: UInt32, onPress: @escaping () -> Void) {
        self.onPress = onPress
        self.hotKeyID = EventHotKeyID(signature: 0x4F54_544F /* 'OTTO' */, id: HotKey.nextID)
        HotKey.nextID += 1

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                var pressedID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil,
                    &pressedID
                )
                guard pressedID.signature == hotKey.hotKeyID.signature,
                      pressedID.id == hotKey.hotKeyID.id else {
                    return OSStatus(eventNotHandledErr)
                }
                hotKey.onPress()
                return noErr
            },
            1, &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installed == noErr else { return nil }

        let registered = RegisterEventHotKey(
            keyCode, carbonModifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registered == noErr, hotKeyRef != nil else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
