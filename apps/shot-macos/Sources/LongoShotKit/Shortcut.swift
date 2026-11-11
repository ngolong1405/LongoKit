import AppKit
import Carbon.HIToolbox
import LongoKitUI

/// A key combination the user picked for an action: a `kVK_` key code and Carbon modifier flags.
struct Shortcut: Codable, Hashable {
    var keyCode: Int
    var modifiers: Int

    static let modifierMask = cmdKey | shiftKey | optionKey | controlKey

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.modifierMask
    }

    init(event: NSEvent) {
        self.init(keyCode: Int(event.keyCode), modifiers: Self.carbon(event.modifierFlags))
    }

    static func carbon(_ flags: NSEvent.ModifierFlags) -> Int {
        var value = 0
        if flags.contains(.command) { value |= cmdKey }
        if flags.contains(.shift) { value |= shiftKey }
        if flags.contains(.option) { value |= optionKey }
        if flags.contains(.control) { value |= controlKey }
        return value
    }

    /// F1–F19 work on their own; any other key needs at least one of ⌘ ⌥ ⌃ ⇧, or it would stop typing that key.
    var isAllowed: Bool { modifiers != 0 || Self.functionKeys.contains(keyCode) }

    /// "⌥⇧1", in the order macOS menus show them.
    var symbols: String { Self.symbols(modifiers) + Self.keyName(keyCode) }

    static func symbols(_ modifiers: Int) -> String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s
    }

    /// Whether macOS itself uses this combination (Mission Control, screenshots, Spotlight, input sources…).
    var isSystemShortcut: Bool {
        var list: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&list) == noErr, let entries = list?.takeRetainedValue() as? [[String: Any]] else { return false }
        return entries.contains { entry in
            (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true
                && (entry[kHISymbolicHotKeyCode as String] as? Int) == keyCode
                && ((entry[kHISymbolicHotKeyModifiers as String] as? Int) ?? 0) & Self.modifierMask == modifiers
        }
    }

    static let functionKeys: Set<Int> = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                         kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19]

    private static let specialNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_KeypadEnter: "⌤",
        ]
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19]
        for (i, code) in fKeys.enumerated() { names[code] = "F\(i + 1)" }
        return names
    }()

    /// The key's label on the current keyboard layout ("1", "A", "Ă"), or its symbol for keys without a character.
    static func keyName(_ keyCode: Int) -> String {
        if let name = specialNames[keyCode] { return name }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(keyCode)" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "#\(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// Everything a shortcut can run.
enum ShotAction: String, CaseIterable, Codable, Identifiable {
    case captureArea, captureScreen, captureText, record, pauseRecording, annotateLast, copyLast, openFolder, openSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captureArea: return L("Capture Area or Window")
        case .captureScreen: return L("Capture Full Screen")
        case .captureText: return L("Copy Text (OCR)")
        case .record: return L("Record Screen")
        case .pauseRecording: return L("Pause / Resume Recording")
        case .annotateLast: return L("Draw on Last Capture")
        case .copyLast: return L("Copy Last Capture")
        case .openFolder: return L("Open Save Folder")
        case .openSettings: return L("Open Settings")
        }
    }

    var detail: String {
        switch self {
        case .captureArea: return L("Drag over an area, or click a window to capture it with its shadow; double-click for the whole screen.")
        case .captureScreen: return L("The whole screen under the pointer.")
        case .captureText: return L("Drag over text: it's read on this Mac and copied, ready to paste.")
        case .record: return L("Drag an area and adjust it, then Start; double-click for the whole screen. The same shortcut stops it.")
        case .pauseRecording: return L("Holds the recording and goes on from the same moment; the pause isn't in the video.")
        case .annotateLast: return L("Arrows, pen, boxes and highlights in a few colors; Done saves over it and copies it.")
        case .copyLast: return L("Puts the last capture on the clipboard again.")
        case .openFolder: return L("Shows the folder captures are saved in.")
        case .openSettings: return L("Opens this window, even with the menu bar icon hidden.")
        }
    }

    var symbol: String {
        switch self {
        case .captureArea: return "rectangle.dashed"
        case .captureScreen: return "display"
        case .captureText: return "text.viewfinder"
        case .record: return "record.circle"
        case .pauseRecording: return "pause.circle"
        case .annotateLast: return "pencil.tip.crop.circle"
        case .copyLast: return "doc.on.clipboard"
        case .openFolder: return "folder"
        case .openSettings: return "gearshape"
        }
    }

    var defaultShortcut: Shortcut? {
        let optionShift = optionKey | shiftKey
        switch self {
        case .captureArea: return Shortcut(keyCode: kVK_ANSI_1, modifiers: optionShift)
        case .captureScreen: return Shortcut(keyCode: kVK_ANSI_2, modifiers: optionShift)
        case .captureText: return Shortcut(keyCode: kVK_ANSI_3, modifiers: optionShift)
        case .record: return Shortcut(keyCode: kVK_ANSI_4, modifiers: optionShift)
        case .openSettings: return Shortcut(keyCode: kVK_ANSI_0, modifiers: optionShift)
        // Pause is on the recording bar and in the menu while recording; a shortcut is there to set if wanted.
        case .pauseRecording, .annotateLast, .copyLast, .openFolder: return nil
        }
    }

    /// What 0.1 set up by default (area, window, screen, text, record, settings on ⌥⇧1–5 and ⌥⇧0). Shortcuts left
    /// like that move to the current defaults; changed ones are kept.
    static let defaults01: [String: Shortcut] = {
        let optionShift = optionKey | shiftKey
        return ["captureArea": Shortcut(keyCode: kVK_ANSI_1, modifiers: optionShift),
                "captureWindow": Shortcut(keyCode: kVK_ANSI_2, modifiers: optionShift),
                "captureScreen": Shortcut(keyCode: kVK_ANSI_3, modifiers: optionShift),
                "captureText": Shortcut(keyCode: kVK_ANSI_4, modifiers: optionShift),
                "record": Shortcut(keyCode: kVK_ANSI_5, modifiers: optionShift),
                "openSettings": Shortcut(keyCode: kVK_ANSI_0, modifiers: optionShift)]
    }()

    static var defaultShortcuts: [ShotAction: Shortcut] {
        Dictionary(uniqueKeysWithValues: allCases.compactMap { action in action.defaultShortcut.map { (action, $0) } })
    }

    /// Hot key ids start at 1.
    var hotKeyID: UInt32 { UInt32(Self.allCases.firstIndex(of: self)! + 1) }
}
