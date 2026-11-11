import Carbon.HIToolbox

/// A system-wide key combination (Carbon hot key): works in any app and needs no permission, so it stays usable
/// as a way out even when Accessibility isn't granted. Unregistered when released.
public final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    /// Unique in the process.
    public let id: UInt32
    private let action: () -> Void
    private static let signature = OSType(0x4C4B4954) // "LKIT"
    /// Ids are handed out here, so they're unique in the process even with several modules in one app.
    private static var lastID: UInt32 = 0

    /// False when macOS refused the combination, usually because another app already took it.
    public var isRegistered: Bool { hotKey != nil }

    /// `keyCode` is a `kVK_` code; `modifiers` are Carbon flags (`cmdKey | optionKey | controlKey`). Every handler sees
    /// every press and only acts on its own id.
    public init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        Self.lastID += 1
        self.id = Self.lastID
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
    public convenience init(controlOptionCommand keyCode: Int, action: @escaping () -> Void) {
        self.init(keyCode: keyCode, modifiers: cmdKey | optionKey | controlKey, action: action)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
