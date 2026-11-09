import Carbon.HIToolbox
import Foundation

/// One key: its HID usage (what `UserKeyMapping` speaks, keyboard page 7) and its macOS virtual key code (what
/// the event tap and NSEvent see).
struct Key: Hashable, Codable, Identifiable {
    let usage: UInt32
    var id: UInt32 { usage }

    /// The full usage `UserKeyMapping` expects: page 7 in the high bits.
    var mappingValue: UInt64 { 0x7_0000_0000 | UInt64(usage) }

    var name: String { Key.names[usage] ?? String(format: "0x%02X", usage) }
    var keyCode: Int? { Key.keyCodes[usage] }

    static func usage(forKeyCode code: Int) -> Key? {
        keyCodes.first { $0.value == code }.map { Key(usage: $0.key) }
    }

    // MARK: The keys LongoKeys knows by name.

    static let escape = Key(usage: 0x29)
    static let capsLock = Key(usage: 0x39)
    static let returnKey = Key(usage: 0x28)
    static let tab = Key(usage: 0x2B)
    static let space = Key(usage: 0x2C)
    static let delete = Key(usage: 0x2A)
    static let forwardDelete = Key(usage: 0x4C)
    static let leftControl = Key(usage: 0xE0), leftShift = Key(usage: 0xE1), leftOption = Key(usage: 0xE2), leftCommand = Key(usage: 0xE3)
    static let rightControl = Key(usage: 0xE4), rightShift = Key(usage: 0xE5), rightOption = Key(usage: 0xE6), rightCommand = Key(usage: 0xE7)
    static let left = Key(usage: 0x50), right = Key(usage: 0x4F), down = Key(usage: 0x51), up = Key(usage: 0x52)
    static let home = Key(usage: 0x4A), end = Key(usage: 0x4D), pageUp = Key(usage: 0x4B), pageDown = Key(usage: 0x4E)
    /// F18: what Caps Lock becomes when it's the Hyper key; nothing on a Mac uses it.
    static let f18 = Key(usage: 0x6D)
    static let k = Key(usage: 0x0E)

    static func letter(_ c: Character) -> Key {
        Key(usage: 0x04 + UInt32(c.asciiValue! - Character("a").asciiValue!))
    }

    private static let names: [UInt32: String] = {
        var names: [UInt32: String] = [
            0x29: "Esc", 0x39: "Caps Lock", 0x28: "Return", 0x2B: "Tab", 0x2C: "Space", 0x2A: "Delete", 0x4C: "⌦",
            0xE0: "Left ⌃", 0xE1: "Left ⇧", 0xE2: "Left ⌥", 0xE3: "Left ⌘",
            0xE4: "Right ⌃", 0xE5: "Right ⇧", 0xE6: "Right ⌥", 0xE7: "Right ⌘",
            0x50: "←", 0x4F: "→", 0x51: "↓", 0x52: "↑", 0x4A: "Home", 0x4D: "End", 0x4B: "Page Up", 0x4E: "Page Down",
            0x2D: "-", 0x2E: "=", 0x2F: "[", 0x30: "]", 0x31: "\\", 0x33: ";", 0x34: "'", 0x35: "`", 0x36: ",", 0x37: ".", 0x38: "/",
            0x64: "§",
        ]
        for (i, c) in "abcdefghijklmnopqrstuvwxyz".enumerated() { names[0x04 + UInt32(i)] = String(c).uppercased() }
        for (i, c) in "1234567890".enumerated() { names[0x1E + UInt32(i)] = String(c) }
        for i in 0..<12 { names[0x3A + UInt32(i)] = "F\(i + 1)" }
        for i in 0..<7 { names[0x68 + UInt32(i)] = "F\(i + 13)" }
        return names
    }()

    private static let keyCodes: [UInt32: Int] = {
        var codes: [UInt32: Int] = [
            0x29: kVK_Escape, 0x39: kVK_CapsLock, 0x28: kVK_Return, 0x2B: kVK_Tab, 0x2C: kVK_Space, 0x2A: kVK_Delete,
            0x4C: kVK_ForwardDelete,
            0xE0: kVK_Control, 0xE1: kVK_Shift, 0xE2: kVK_Option, 0xE3: kVK_Command,
            0xE4: kVK_RightControl, 0xE5: kVK_RightShift, 0xE6: kVK_RightOption, 0xE7: kVK_RightCommand,
            0x50: kVK_LeftArrow, 0x4F: kVK_RightArrow, 0x51: kVK_DownArrow, 0x52: kVK_UpArrow,
            0x4A: kVK_Home, 0x4D: kVK_End, 0x4B: kVK_PageUp, 0x4E: kVK_PageDown,
            0x2D: kVK_ANSI_Minus, 0x2E: kVK_ANSI_Equal, 0x2F: kVK_ANSI_LeftBracket, 0x30: kVK_ANSI_RightBracket,
            0x31: kVK_ANSI_Backslash, 0x33: kVK_ANSI_Semicolon, 0x34: kVK_ANSI_Quote, 0x35: kVK_ANSI_Grave,
            0x36: kVK_ANSI_Comma, 0x37: kVK_ANSI_Period, 0x38: kVK_ANSI_Slash, 0x64: kVK_ISO_Section,
        ]
        let letters = [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H,
                       kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P,
                       kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
                       kVK_ANSI_Y, kVK_ANSI_Z]
        for (i, code) in letters.enumerated() { codes[0x04 + UInt32(i)] = code }
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8,
                      kVK_ANSI_9, kVK_ANSI_0]
        for (i, code) in digits.enumerated() { codes[0x1E + UInt32(i)] = code }
        let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
                     kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19]
        for (i, code) in fKeys.enumerated() { codes[(i < 12 ? 0x3A : 0x68 - 12) + UInt32(i)] = code }
        return codes
    }()
}

/// What Caps Lock does on a keyboard.
enum CapsMode: String, Codable, CaseIterable {
    case unchanged
    case escape
    case control
    /// Tap: Esc. Hold: Hyper (⌃⌥⇧⌘), and the Hyper layer's actions.
    case hyper
}

/// One key turned into another on a keyboard.
struct Remap: Codable, Hashable {
    var from: Key
    var to: Key
}

/// What a keyboard does: its remaps and its Caps Lock.
struct KeyboardProfile: Codable, Equatable {
    var remaps: [Remap] = []
    var caps: CapsMode = .unchanged

    init(remaps: [Remap] = [], caps: CapsMode = .unchanged) {
        self.remaps = remaps
        self.caps = caps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        remaps = try c.decodeIfPresent([Remap].self, forKey: .remaps) ?? []
        caps = (try? c.decodeIfPresent(CapsMode.self, forKey: .caps)) ?? .unchanged
    }

    func target(of key: Key) -> Key? { remaps.first { $0.from == key }?.to }

    /// The key → key table this profile gives `UserKeyMapping`. `hyperReady` is whether the event tap that turns
    /// F18 into Hyper is running: without it Caps Lock is left alone instead of becoming a key that does nothing.
    func mapping(hyperReady: Bool) -> [Key: Key] {
        var table: [Key: Key] = [:]
        for remap in remaps where remap.from != remap.to { table[remap.from] = remap.to }
        switch caps {
        case .unchanged: break
        case .escape: table[.capsLock] = .escape
        case .control: table[.capsLock] = .leftControl
        case .hyper: if hyperReady { table[.capsLock] = .f18 } else { table[.capsLock] = nil }
        }
        return table
    }

    /// Keys a keyboard must still be able to type, so it can always be used and LongoKeys paused (⌃⌥⌘K).
    static let essentials: [Key] = [.escape, .returnKey, .leftCommand, .leftControl, .leftOption, .k]

    /// Why this profile isn't allowed, or nil. Every essential key must still come out of some physical key.
    func problem(physicalKeys: Set<Key>) -> String? {
        let table = mapping(hyperReady: true)
        var produced = Set(physicalKeys.map { table[$0] ?? $0 })
        if caps == .hyper { produced.insert(.escape) } // a tap on Caps Lock
        // Either side of a modifier will do.
        let sides: [Key: Key] = [.leftCommand: .rightCommand, .leftControl: .rightControl, .leftOption: .rightOption]
        for key in Self.essentials where !produced.contains(key) && !(sides[key].map(produced.contains) ?? false) {
            return key.name
        }
        return nil
    }

    // MARK: Presets

    static let swapCommandOption: [Remap] = [
        Remap(from: .leftCommand, to: .leftOption), Remap(from: .leftOption, to: .leftCommand),
        Remap(from: .rightCommand, to: .rightOption), Remap(from: .rightOption, to: .rightCommand),
    ]

    var swapsCommandOption: Bool { Self.swapCommandOption.allSatisfy(remaps.contains) }
}

/// What a key does while Hyper (Caps Lock) is held.
enum HyperAction: Codable, Hashable {
    case key(Key)
    case openApp(path: String)
    case shortcut(keyCode: Int, flags: UInt64, label: String)
    /// The next keyboard input source, e.g. English ↔ Vietnamese.
    case nextInputSource
}

struct HyperBinding: Codable, Hashable, Identifiable {
    var trigger: Key
    var action: HyperAction
    var id: UInt32 { trigger.usage }

    static let defaults: [HyperBinding] = [
        HyperBinding(trigger: .letter("h"), action: .key(.left)),
        HyperBinding(trigger: .letter("j"), action: .key(.down)),
        HyperBinding(trigger: .letter("k"), action: .key(.up)),
        HyperBinding(trigger: .letter("l"), action: .key(.right)),
        HyperBinding(trigger: .letter("u"), action: .key(.home)),
        HyperBinding(trigger: .letter("o"), action: .key(.end)),
        HyperBinding(trigger: .space, action: .nextInputSource),
    ]
}
