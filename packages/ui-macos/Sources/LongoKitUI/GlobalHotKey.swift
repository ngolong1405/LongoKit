import Carbon.HIToolbox

/// A system-wide key combination (Carbon hot key): works in any app and needs no permission, so it stays usable
/// as a way out even when Accessibility isn't granted. Unregistered when released.
public final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// `keyCode` is a `kVK_` code; `modifiers` are Carbon flags (`cmdKey | optionKey | controlKey`).
    public init(keyCode: Int, modifiers: Int, id: UInt32, action: @escaping () -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            Unmanaged<GlobalHotKey>.fromOpaque(context!).takeUnretainedValue().action()
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: OSType(0x4C4B4954), id: id), // "LKIT"
                            GetApplicationEventTarget(), 0, &hotKey)
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
