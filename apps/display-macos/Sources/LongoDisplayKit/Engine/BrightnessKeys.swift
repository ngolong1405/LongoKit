import AppKit
import CoreGraphics

/// Catches the brightness keys (F1/F2 on Apple keyboards) so they can control the display under the pointer.
/// Needs Accessibility. Keys pressed while the pointer is on a display macOS already controls pass through.
final class BrightnessKeys {
    /// Called on key down with `up: true` for brighter; return true to swallow the key.
    var handler: ((_ up: Bool) -> Bool)?
    private var tap: CFMachPort?

    var isRunning: Bool { tap != nil }

    // NX_SYSDEFINED events carry media and brightness keys; subtype 8 is the auxiliary control buttons.
    private static let systemDefined = CGEventType(rawValue: 14)!
    private static let brightnessUp = 2
    private static let brightnessDown = 3

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1) << Self.systemDefined.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, context in
                let keys = Unmanaged<BrightnessKeys>.fromOpaque(context!).takeUnretainedValue()
                return keys.handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard type == Self.systemDefined, let key = Self.decode(event) else { return pass }
        // A swallowed key down takes its key up with it, so macOS never sees half a key press.
        if key.down { swallowing = handler?(key.up) ?? false }
        return swallowing ? nil : pass
    }

    private var swallowing = false

    /// Brightness key direction and whether it's a key down, or nil for any other system-defined event.
    static func decode(_ event: CGEvent) -> (up: Bool, down: Bool)? {
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return nil }
        let code = (ns.data1 & 0xFFFF_0000) >> 16
        guard code == brightnessUp || code == brightnessDown else { return nil }
        let state = (ns.data1 & 0xFF00) >> 8
        return (code == brightnessUp, state == 0xA)
    }
}
