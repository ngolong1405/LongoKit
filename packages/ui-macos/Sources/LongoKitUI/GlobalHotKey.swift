import Carbon.HIToolbox

/// A system-wide key combination (Carbon hot key): works in any app and needs no permission, so it stays usable
/// as a way out even when Accessibility isn't granted. Unregistered when released.
public final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id: UInt32
    private let action: () -> Void
    private static let signature = OSType(0x4C4B4954) // "LKIT"

    /// False when macOS refused the combination, usually because another app already took it.
    public var isRegistered: Bool { hotKey != nil }

    /// `keyCode` is a `kVK_` code; `modifiers` are Carbon flags (`cmdKey | optionKey | controlKey`). Each hot key in
    /// an app needs its own `id`: every handler sees every press and only acts on its own.
    public init(keyCode: Int, modifiers: Int, id: UInt32, action: @escaping () -> Void) {
        self.id = id
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            let me = Unmanaged<GlobalHotKey>.fromOpaque(context!).takeUnretainedValue()
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            // Someone else's hot key: let the next handler have it.
            guard pressed.signature == GlobalHotKey.signature, pressed.id == me.id else { return OSStatus(eventNotHandledErr) }
            me.action()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { hotKey = nil }
    }

    /// ⌃⌥⌘ plus a key.
    public convenience init(controlOptionCommand keyCode: Int, id: UInt32, action: @escaping () -> Void) {
        self.init(keyCode: keyCode, modifiers: cmdKey | optionKey | controlKey, id: id, action: action)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
