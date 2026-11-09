import AppKit
import Carbon.HIToolbox

/// `LongoKeys --selftest` checks key tables, the safety rules and the Hyper key with synthetic events.
/// Nothing reaches any keyboard: HyperTap reports into a recorder instead of posting.
enum SelfTest {
    static var isRequested: Bool { CommandLine.arguments.contains("--selftest") }
    private static var failures = 0

    @MainActor
    static func runAndExit() {
        // Key tables.
        check("Caps Lock is usage 0x39 on page 7", Key.capsLock.mappingValue == 0x7_0000_0039)
        check("H is key code kVK_ANSI_H", Key.letter("h").keyCode == kVK_ANSI_H)
        check("F18 round-trips through its key code", Key.usage(forKeyCode: kVK_F18) == .f18)
        check("F13 and F19 are named", Key(usage: 0x68).name == "F13" && Key(usage: 0x6E).name == "F19")
        let array = KeyMapper.mappingArray([.capsLock: .escape])
        check("UserKeyMapping entry", array == [["HIDKeyboardModifierMappingSrc": 0x7_0000_0039, "HIDKeyboardModifierMappingDst": 0x7_0000_0029]])

        // Caps Lock modes.
        check("Caps → Esc", KeyboardProfile(caps: .escape).mapping(hyperReady: true) == [.capsLock: .escape])
        check("Caps → Hyper becomes F18 once the tap runs", KeyboardProfile(caps: .hyper).mapping(hyperReady: true) == [.capsLock: .f18])
        check("Caps → Hyper leaves Caps Lock alone without the tap", KeyboardProfile(caps: .hyper).mapping(hyperReady: false).isEmpty)
        check("Swap ⌘ ⌥ preset", KeyboardProfile(remaps: KeyboardProfile.swapCommandOption).mapping(hyperReady: true)[.leftCommand] == .leftOption)

        // Safety: every keyboard keeps Esc, Return, ⌘, ⌃, ⌥ and K.
        let keys = KeyboardLayout.physicalKeys
        check("Swapping ⌘ and ⌥ is allowed", KeyboardProfile(remaps: KeyboardProfile.swapCommandOption).problem(physicalKeys: keys) == nil)
        check("Losing Esc is refused", KeyboardProfile(remaps: [Remap(from: .escape, to: .tab)]).problem(physicalKeys: keys) == "Esc")
        check("…unless Caps Lock gives Esc", KeyboardProfile(remaps: [Remap(from: .escape, to: .tab)], caps: .escape).problem(physicalKeys: keys) == nil)
        check("…or Caps Lock is Hyper (tap = Esc)", KeyboardProfile(remaps: [Remap(from: .escape, to: .tab)], caps: .hyper).problem(physicalKeys: keys) == nil)
        check("Losing K is refused (⌃⌥⌘K)", KeyboardProfile(remaps: [Remap(from: .k, to: .letter("j"))]).problem(physicalKeys: keys) == "K")
        check("One ⌘ is enough", KeyboardProfile(remaps: [Remap(from: .leftCommand, to: .leftOption)]).problem(physicalKeys: keys) == nil)
        check("Losing both ⌘ is refused", KeyboardProfile(remaps: [Remap(from: .leftCommand, to: .leftOption),
                                                                  Remap(from: .rightCommand, to: .rightOption)]).problem(physicalKeys: keys) == "Left ⌘")
        let old = try? JSONDecoder().decode(KeyboardProfile.self, from: Data(#"{"remaps":[]}"#.utf8))
        check("Old settings load with defaults", old?.caps == .unchanged)

        // The Hyper key.
        let tap = HyperTap.shared
        var recorded: [String] = []
        HyperTap.recorder = { recorded.append($0) }
        var clock = Date()
        tap.now = { clock }
        var bindings: [Int: HyperAction] = [:]
        for binding in HyperBinding.defaults { bindings[binding.trigger.keyCode!] = binding.action }
        tap.bindings = bindings
        func key(_ code: Int, _ down: Bool, flags: CGEventFlags = []) -> (swallowed: Bool, event: CGEvent) {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)!
            event.flags = flags
            return (tap.process(down ? .keyDown : .keyUp, event), event)
        }

        tap.reset(); recorded = []
        let f18Down = key(kVK_F18, true).swallowed
        clock += 0.1
        let f18Up = key(kVK_F18, false).swallowed
        check("Hyper tapped alone sends Esc (and F18 never reaches apps)", f18Down && f18Up && recorded == ["key \(kVK_Escape)"])

        tap.reset(); recorded = []
        _ = key(kVK_F18, true)
        let jDown = key(kVK_ANSI_J, true).swallowed, jUp = key(kVK_ANSI_J, false).swallowed
        _ = key(kVK_F18, false)
        check("Hyper + J sends ↓ and nothing else", jDown && jUp && recorded == ["key \(kVK_DownArrow)"])

        tap.reset(); recorded = []
        _ = key(kVK_F18, true)
        let x = key(kVK_ANSI_X, true)
        let xUp = key(kVK_ANSI_X, false)
        _ = key(kVK_F18, false)
        check("Hyper + an unbound key sends it with ⌃⌥⇧⌘", !x.swallowed && x.event.flags.isSuperset(of: HyperTap.hyperFlags)
              && xUp.event.flags.isSuperset(of: HyperTap.hyperFlags) && recorded.isEmpty)

        tap.reset(); recorded = []
        _ = key(kVK_F18, true)
        clock += 1
        _ = key(kVK_F18, false)
        check("Hyper held a while and let go does nothing", recorded.isEmpty)

        tap.reset(); recorded = []
        let plain = key(kVK_ANSI_J, true)
        check("Keys without Hyper pass untouched", !plain.swallowed && plain.event.flags.isEmpty && recorded.isEmpty)

        tap.isEnabled = false
        let paused = key(kVK_F18, true).swallowed
        tap.isEnabled = true
        check("Paused, the tap lets everything through", !paused)

        tap.reset(); recorded = []
        _ = key(kVK_F18, true)
        _ = tap.process(.tapDisabledByTimeout, CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!)
        let afterTimeout = key(kVK_ANSI_J, true)
        check("macOS pausing the tap lets go of Hyper", !afterTimeout.swallowed && recorded.isEmpty)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    /// `LongoKeys --diagnose`: keyboards, their current key tables, and permissions (for bug reports).
    static var isDiagnoseRequested: Bool { CommandLine.arguments.contains("--diagnose") }

    @MainActor
    static func diagnoseAndExit() {
        for keyboard in KeyboardMonitor().snapshot() {
            print("\(keyboard.name) [\(keyboard.connection)] \(String(format: "%04X:%04X", keyboard.vendorID, keyboard.productID)) · id \(keyboard.id)")
        }
        for (name, count) in KeyMapper.current() { print("service \(name): \(count) mapped keys") }
        print("Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted") · Secure Input: \(IsSecureEventInputEnabled() ? "on" : "off")")
        exit(0)
    }

    private static func check(_ name: String, _ ok: Bool) {
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(name)")
    }
}
