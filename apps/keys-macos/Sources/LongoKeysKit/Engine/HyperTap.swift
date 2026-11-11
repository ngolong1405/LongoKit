import AppKit
import Carbon.HIToolbox

/// Turns F18 (what Caps Lock becomes on keyboards set to Hyper) into the Hyper key, through a CGEventTap:
/// - tapped alone: Esc
/// - held with another key: that key's Hyper action (arrows, apps, …), or the key with ⌃⌥⇧⌘ added
/// The tap runs on the main run loop, so its state is only touched from the main thread. It needs Accessibility.
/// macOS doesn't show keystrokes to taps while a password field has Secure Input on: then Caps Lock does nothing
/// until the field loses focus, and the app says so.
final class HyperTap {
    static let shared = HyperTap()

    var isEnabled = true {
        didSet { if !isEnabled { reset() } }
    }
    /// Hyper actions by the key code of the key pressed with Hyper.
    var bindings: [Int: HyperAction] = [:]

    /// Released within this long without another key, Hyper is a tap: Esc.
    static let tapWindow: TimeInterval = 0.5
    static let hyperFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
    /// Stamped on events we post so the tap lets them through.
    static let syntheticTag: Int64 = 0x4C4B_4559 // "LKEY"

    /// Self-test only: actions are reported here instead of being sent to the system.
    static var recorder: ((String) -> Void)?
    /// While the key tester listens: the top row's system keys (brightness, Mission Control, media, volume…) are
    /// reported here as the F key they sit on, and kept from macOS so they don't act. Nil the rest of the time.
    var listener: ((_ fKey: Int, _ action: String, _ down: Bool) -> Void)?

    /// Self-test only: the clock, so tap timing can be checked without waiting.
    var now: () -> Date = Date.init

    private var tap: CFMachPort?
    private var hyperDown: Date?
    private var hyperUsed = false
    /// Keys whose key-down was turned into an action: their key-up is swallowed too.
    private var swallowed: Set<Int64> = []
    /// Keys that went out with Hyper's modifiers: their key-up gets them too.
    private var withHyper: Set<Int64> = []

    var isRunning: Bool { tap != nil }
    var isHyperHeld: Bool { hyperDown != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.keyDown, .keyUp]
        // NX_SYSDEFINED (14): brightness, media and volume keys, for the key tester.
        let mask = types.reduce(CGEventMask(1) << 14) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                Unmanaged<HyperTap>.fromOpaque(refcon!).takeUnretainedValue().handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    /// Self-test entry point: runs an event through the tap; true when it was swallowed.
    func process(_ type: CGEventType, _ event: CGEvent) -> Bool {
        handle(type, event) == nil
    }

    func reset() {
        hyperDown = nil
        hyperUsed = false
        swallowed.removeAll()
        withHyper.removeAll()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Keys were missed while off: start clean rather than leave Hyper stuck down.
            reset()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if let listener, let (fKey, action, down) = Self.topRowKey(type, event) {
            listener(fKey, action, down)
            return nil
        }
        guard isEnabled, type == .keyDown || type == .keyUp,
              event.getIntegerValueField(.eventSourceUserData) != Self.syntheticTag else { return pass }
        let code = event.getIntegerValueField(.keyboardEventKeycode)

        if code == Int64(kVK_F18) {
            if type == .keyDown {
                if hyperDown == nil {
                    hyperDown = now()
                    hyperUsed = false
                }
            } else if type == .keyUp, let down = hyperDown {
                if !hyperUsed && now().timeIntervalSince(down) < Self.tapWindow {
                    Self.postKey(kVK_Escape, [])
                }
                hyperDown = nil
            }
            return nil
        }

        if type == .keyDown, hyperDown != nil {
            hyperUsed = true
            if let action = bindings[Int(code)] {
                swallowed.insert(code)
                Self.perform(action)
                return nil
            }
            withHyper.insert(code)
            event.flags.formUnion(Self.hyperFlags)
            return pass
        }
        if type == .keyUp {
            if swallowed.remove(code) != nil { return nil }
            if withHyper.remove(code) != nil { event.flags.formUnion(Self.hyperFlags) }
        }
        return pass
    }

    // MARK: The top row's system keys

    /// Aux control buttons (NX_KEYTYPE_*) by the F key they sit on, on Apple keyboards.
    private static let auxKeys: [Int: (Int, String)] = [
        3: (1, "Brightness down"), 2: (2, "Brightness up"),
        21: (5, "Keyboard light down"), 22: (6, "Keyboard light up"),
        20: (7, "Previous track"), 18: (7, "Previous track"), 16: (8, "Play / Pause"),
        19: (9, "Next track"), 17: (9, "Next track"),
        7: (10, "Mute"), 1: (11, "Volume down"), 0: (12, "Volume up"),
    ]

    /// Special key codes some Apple keyboards send from the top row.
    private static let specialKeys: [Int64: (Int, String)] = [
        160: (3, "Mission Control"), 131: (4, "Launchpad"), 177: (4, "Spotlight"),
        176: (5, "Dictation"), 178: (6, "Do Not Disturb"),
    ]

    /// A top-row system key in this event: its F number, what it does, and whether it's going down.
    static func topRowKey(_ type: CGEventType, _ event: CGEvent) -> (Int, String, Bool)? {
        if type.rawValue == 14 {
            guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return nil }
            let data = ns.data1
            guard let (fKey, action) = auxKeys[(data & 0xFFFF_0000) >> 16] else { return nil }
            return (fKey, action, (data & 0xFF00) >> 8 == 0x0A)
        }
        guard type == .keyDown || type == .keyUp,
              let (fKey, action) = specialKeys[event.getIntegerValueField(.keyboardEventKeycode)] else { return nil }
        return (fKey, action, type == .keyDown)
    }

    // MARK: Actions

    static func perform(_ action: HyperAction) {
        switch action {
        case .key(let key):
            if let code = key.keyCode { postKey(code, []) }
        case .openApp(let path):
            if let recorder { return recorder("open \((path as NSString).lastPathComponent)") }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
        case .shortcut(let code, let flags, _):
            postKey(code, CGEventFlags(rawValue: flags))
        case .nextInputSource:
            if let recorder { return recorder("input source") }
            InputSources.selectNext()
        }
    }

    static func postKey(_ code: Int, _ flags: CGEventFlags) {
        if let recorder { return recorder("key \(code)\(flags.isEmpty ? "" : "+\(flags.rawValue)")") }
        var flags = flags
        // Real arrow and navigation keys carry these; some apps ignore them otherwise.
        if (kVK_Home...kVK_UpArrow).contains(code) || [kVK_ForwardDelete].contains(code) {
            flags.formUnion([.maskSecondaryFn, .maskNumericPad])
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
            event.post(tap: .cghidEventTap)
        }
    }
}

/// Keyboard input sources (layouts and input methods such as Vietnamese), for "next input source".
enum InputSources {
    static func selectNext() {
        let filter = [kTISPropertyInputSourceIsSelectCapable as String: true,
                      kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource], list.count > 1,
              let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        let id = { (source: TISInputSource) -> String in
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
            return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        }
        let index = list.firstIndex { id($0) == id(current) } ?? -1
        TISSelectInputSource(list[(index + 1) % list.count])
    }
}
