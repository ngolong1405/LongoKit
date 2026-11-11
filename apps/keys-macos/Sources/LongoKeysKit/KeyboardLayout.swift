/// A Mac keyboard (ANSI), row by row: what the keyboard picture shows and which keys a keyboard physically has.
enum KeyboardLayout {
    struct Cap: Identifiable {
        let key: Key?
        let label: String
        let width: Double
        let id: Int
    }

    static let rows: [[Cap]] = {
        var id = 0
        func cap(_ key: Key?, _ label: String? = nil, _ width: Double = 1) -> Cap {
            id += 1
            return Cap(key: key, label: label ?? key?.name ?? "", width: width, id: id)
        }
        func keys(_ letters: String) -> [Cap] {
            letters.map { c in
                if let letter = c.asciiValue, ("a"..."z").contains(c) { _ = letter; return cap(.letter(c)) }
                let usage: UInt32 = ["`": 0x35, "1": 0x1E, "2": 0x1F, "3": 0x20, "4": 0x21, "5": 0x22, "6": 0x23, "7": 0x24,
                                     "8": 0x25, "9": 0x26, "0": 0x27, "-": 0x2D, "=": 0x2E, "[": 0x2F, "]": 0x30, "\\": 0x31,
                                     ";": 0x33, "'": 0x34, ",": 0x36, ".": 0x37, "/": 0x38][c]!
                return cap(Key(usage: usage))
            }
        }
        let fRow = [cap(.escape, "esc", 1.5)] + (0..<12).map { cap(Key(usage: 0x3A + UInt32($0)), "F\($0 + 1)") }
        return [
            fRow,
            keys("`1234567890-=") + [cap(.delete, "delete", 1.5)],
            [cap(.tab, "tab", 1.5)] + keys("qwertyuiop[]\\"),
            [cap(.capsLock, "caps lock", 1.8)] + keys("asdfghjkl;'") + [cap(.returnKey, "return", 1.75)],
            [cap(.leftShift, "shift", 2.3)] + keys("zxcvbnm,./") + [cap(.rightShift, "shift", 2.3)],
            [cap(nil, "fn"), cap(.leftControl, "⌃"), cap(.leftOption, "⌥"), cap(.leftCommand, "⌘", 1.3),
             cap(.space, "", 5), cap(.rightCommand, "⌘", 1.3), cap(.rightOption, "⌥"),
             cap(.left, "←"), cap(.up, "↑"), cap(.down, "↓"), cap(.right, "→")],
        ]
    }()

    static let physicalKeys: Set<Key> = Set(rows.flatMap { $0.compactMap(\.key) })

    /// What a key can be turned into, grouped for the picker.
    static let targets: [(String, [Key])] = [
        ("Keys", [.escape, .tab, .returnKey, .delete, .forwardDelete, .space, .capsLock]),
        ("Modifiers", [.leftControl, .leftOption, .leftCommand, .leftShift, .rightControl, .rightOption, .rightCommand, .rightShift]),
        ("Navigation", [.left, .right, .up, .down, .home, .end, .pageUp, .pageDown]),
        ("Extra F keys", (0..<7).map { Key(usage: 0x68 + UInt32($0)) }),
    ]
}
