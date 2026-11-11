import Carbon.HIToolbox

/// Some mice send a side button as a key combo instead of a mouse button (UGREEN mice send ⌃← and ⌃→,
/// which switch Spaces). DeviceMonitor sees those keys arrive from the mouse itself, and the engine treats
/// each combo as one more button, so it can be listened for and remapped like any other.
enum MouseKeys {
    /// Buttons made from key combos are numbered from here: base + (HID modifier bits << 8) + HID key usage.
    static let base = 0x10000

    static func button(usage: Int, modifiers: Int) -> Int { base + (modifiers << 8) + usage }
    static func isKeyButton(_ button: Int) -> Bool { button >= base }
    static func usage(of button: Int) -> Int { (button - base) & 0xFF }
    static func modifiers(of button: Int) -> Int { (button - base) >> 8 }

    /// "⌃→": what the combo of a key button looks like.
    static func symbol(of button: Int) -> String {
        let mods = modifiers(of: button)
        var s = ""
        if mods & 0x11 != 0 { s += "⌃" }
        if mods & 0x44 != 0 { s += "⌥" }
        if mods & 0x22 != 0 { s += "⇧" }
        if mods & 0x88 != 0 { s += "⌘" }
        let usage = usage(of: button)
        return s + (names[usage] ?? String(format: "0x%02X", usage))
    }

    /// The macOS virtual key code for a HID keyboard usage (page 7).
    static func keyCode(usage: Int) -> UInt16? { keyCodes[usage].map(UInt16.init) }

    /// HID usage for each macOS key code, to match the key events the tap sees with what the mouse sent.
    static func usage(keyCode: UInt16) -> Int? { usages[Int(keyCode)] }

    private static let keyCodes: [Int: Int] = {
        var map: [Int: Int] = [:]
        let letters = [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H,
                       kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P,
                       kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
                       kVK_ANSI_Y, kVK_ANSI_Z]
        for (i, code) in letters.enumerated() { map[0x04 + i] = code }
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                      kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0]
        for (i, code) in digits.enumerated() { map[0x1E + i] = code }
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        for (i, code) in fKeys.enumerated() { map[0x3A + i] = code }
        let others: [Int: Int] = [
            0x28: kVK_Return, 0x29: kVK_Escape, 0x2A: kVK_Delete, 0x2B: kVK_Tab, 0x2C: kVK_Space,
            0x2D: kVK_ANSI_Minus, 0x2E: kVK_ANSI_Equal, 0x2F: kVK_ANSI_LeftBracket, 0x30: kVK_ANSI_RightBracket,
            0x4A: kVK_Home, 0x4B: kVK_PageUp, 0x4C: kVK_ForwardDelete, 0x4D: kVK_End, 0x4E: kVK_PageDown,
            0x4F: kVK_RightArrow, 0x50: kVK_LeftArrow, 0x51: kVK_DownArrow, 0x52: kVK_UpArrow,
        ]
        map.merge(others) { a, _ in a }
        return map
    }()

    private static let usages: [Int: Int] = Dictionary(keyCodes.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })

    private static let names: [Int: String] = {
        var map: [Int: String] = [:]
        for i in 0..<26 { map[0x04 + i] = String(UnicodeScalar(UInt8(65 + i))) }
        for i in 0..<9 { map[0x1E + i] = String(i + 1) }
        map[0x27] = "0"
        for i in 0..<12 { map[0x3A + i] = "F\(i + 1)" }
        let others: [Int: String] = [
            0x28: "↩", 0x29: "⎋", 0x2A: "⌫", 0x2B: "⇥", 0x2C: "Space", 0x2D: "-", 0x2E: "=", 0x2F: "[", 0x30: "]",
            0x4A: "↖", 0x4B: "⇞", 0x4C: "⌦", 0x4D: "↘", 0x4E: "⇟", 0x4F: "→", 0x50: "←", 0x51: "↓", 0x52: "↑",
        ]
        map.merge(others) { a, _ in a }
        return map
    }()
}
