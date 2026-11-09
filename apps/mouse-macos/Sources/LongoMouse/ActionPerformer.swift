import AppKit
import LongoKitUI

enum ActionPerformer {
    /// Stamped on events we post so the event tap lets them through instead of remapping them again.
    static let syntheticTag: Int64 = 0x4D4D_4150 // "MMAP"

    /// Self-test only: when set, actions are reported here instead of being sent to the system.
    static var recorder: ((String) -> Void)?

    /// Runs a single-shot action. Drag and scroll actions are continuous and live in `MouseEngine`.
    static func perform(_ binding: MouseBinding) {
        switch binding.action {
        case .lookUp: postKey(2, [.command, .control]) // ⌃⌘D
        case .primaryClick: postClick(button: 0)
        case .secondaryClick: postClick(button: 1)
        case .middleClick: postClick(button: 2)
        case .back: postKey(33, [.command]) // ⌘[
        case .forward: postKey(30, [.command]) // ⌘]
        case .missionControl: openMissionControl()
        case .appExpose: postKey(125, [.control])
        case .showDesktop: postKey(103, []) // F11
        case .launchpad: openLaunchpad()
        case .spaceLeft: postKey(123, [.control])
        case .spaceRight: postKey(124, [.control])
        case .shortcut:
            if let s = binding.shortcut { postKey(s.keyCode, s.modifiers) }
        case .mediaKey:
            if let key = binding.mediaKey { postMediaKey(key) }
        case .none, .smartZoom, .dragSpaces, .dragMissionControl, .dragScroll,
             .scrollZoom, .scrollSpaces, .scrollHorizontal:
            break
        }
    }

    static func postKey(_ keyCode: UInt16, _ modifiers: Modifiers) {
        if let recorder { return recorder("key \(keyCode)\(modifiers.symbols)") }
        // Real arrow and F-key events carry these flags; system shortcuts like ⌃← ignore them otherwise.
        var flags = modifiers.cgFlags
        if (123...126).contains(keyCode) { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        if fKeyCodes.contains(keyCode) { flags.insert(.maskSecondaryFn) }

        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
            event.post(tap: .cghidEventTap)
        }
    }

    static func postClick(button: Int) {
        if let recorder { return recorder("click \(button)") }
        let location = CGEvent(source: nil)?.location ?? .zero
        let types: [CGEventType]
        switch button {
        case 0: types = [.leftMouseDown, .leftMouseUp]
        case 1: types = [.rightMouseDown, .rightMouseUp]
        default: types = [.otherMouseDown, .otherMouseUp]
        }
        let cgButton = CGMouseButton(rawValue: UInt32(button)) ?? .center
        for type in types {
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                      mouseCursorPosition: location, mouseButton: cgButton) else { continue }
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
            event.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Posts a pixel-based scroll; positive `dy` scrolls content up, positive `dx` scrolls it left.
    static func postScroll(dx: Int32, dy: Int32) {
        if let recorder { return recorder("scroll") }
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
        event.post(tap: .cghidEventTap)
    }

    static func postMediaKey(_ key: MediaKey) {
        if let recorder { return recorder("media \(key.rawValue)") }
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: (key.rawValue << 16) | (state << 8), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    static func openMissionControl() {
        if let recorder { return recorder("missionControl") }
        openApp("/System/Applications/Mission Control.app")
    }

    private static func openLaunchpad() {
        if let recorder { return recorder("launchpad") }
        // macOS 26 replaced Launchpad with the Apps launcher.
        let apps = "/System/Applications/Apps.app"
        openApp(FileManager.default.fileExists(atPath: apps) ? apps : "/System/Applications/Launchpad.app")
    }

    private static func openApp(_ path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    private static let fKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
}
