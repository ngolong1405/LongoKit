import AppKit
import CoreGraphics

/// `LongoDisplay --selftest` checks the parts that don't need a monitor attached: DDC packets, Sync mapping,
/// key steps, and write coalescing. Nothing is sent to any display.
enum SelfTest {
    static var isRequested: Bool { CommandLine.arguments.contains("--selftest") }
    private static var failures = 0

    @MainActor
    static func runAndExit() {
        // DDC packets (VESA MCCS framing as MonitorControl sends it). The last byte is the XOR checksum.
        check("Set brightness 50 packet", DDCChannel.writePacket(0x10, 50) == [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
        check("Get brightness packet", DDCChannel.readPacket(0x10) == [0x82, 0x01, 0x10, 0xFD])
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x2A, 0x00]
        check("Parse reply: current 42 of 100", DDCChannel.parseReply(reply, code: 0x10).map { $0 == (42, 100) } ?? false)
        check("Reject an error reply", DDCChannel.parseReply([0x6E, 0x88, 0x02, 0x01, 0x10, 0, 0, 0x64, 0, 0x2A, 0], code: 0x10) == nil)
        check("Reject a reply for another control", DDCChannel.parseReply(reply, code: 0x12) == nil)

        // Sync mapping.
        check("Sync: built-in 50% → halfway between 20 and 80", abs(SyncMath.map(builtin: 0.5, minimum: 0.2, maximum: 0.8) - 0.5) < 0.0001)
        check("Sync: built-in 0% → minimum", SyncMath.map(builtin: 0, minimum: 0.3, maximum: 1) == 0.3)
        check("Sync: built-in 100% → maximum", SyncMath.map(builtin: 1, minimum: 0, maximum: 0.6) == 0.6)
        check("Sync: swapped limits still map inside them", SyncMath.map(builtin: 1, minimum: 0.9, maximum: 0.1) == 0.9)

        // Brightness keys.
        check("Key up from 50% → 9/16", SyncMath.stepped(0.5, up: true) == 9.0 / 16)
        check("Key down stops at 0", SyncMath.stepped(0, up: false) == 0)
        check("Key up stops at 100%", SyncMath.stepped(1, up: true) == 1)

        // Coalescing: a burst of slider values writes far fewer times and ends on the last value.
        var written: [Int] = []
        let lock = NSLock()
        let done = DispatchSemaphore(value: 0)
        let coalescer = Coalescer<Int>(label: "selftest") { value in
            usleep(20_000)
            lock.lock(); written.append(value); lock.unlock()
            if value == 99 { done.signal() }
        }
        for value in 0...99 { coalescer.submit(value) }
        _ = done.wait(timeout: .now() + 3)
        usleep(50_000)
        lock.lock(); let writes = written; lock.unlock()
        check("Coalescer ends on the last value", writes.last == 99)
        check("Coalescer skips stale values (\(writes.count) writes for 100 changes)", writes.count < 10)

        // Saved settings from an older version still load.
        let old = try? JSONDecoder().decode(DisplaySettings.self, from: Data(#"{"brightness":0.4}"#.utf8))
        check("Old settings load with defaults", old?.brightness == 0.4 && old?.maximum == 1 && old?.extraDim == 0)

        // Display power: the guards that keep a screen on. Nothing is turned off.
        check("Display power API found in SkyLight", DisplayPower.isAvailable)
        check("The only active display can't be turned off", DisplayPower.activeCount() != 1 || !DisplayPower.canTurnOff(CGMainDisplayID()))
        let suite = "LongoDisplay.selftest"
        UserDefaults().removePersistentDomain(forName: suite)
        let model = AppModel(live: false, defaults: UserDefaults(suiteName: suite)!)
        let screens = ["a", "b", "c"].enumerated().map { index, key in
            Display(id: CGDirectDisplayID(index + 1), key: key, name: key, isBuiltin: index == 0, method: .software, pixelSize: .zero)
        }
        model.simulate(displays: screens, settings: [:], powerOff: ["c": .disabled])
        check("With two displays on, either can be turned off", model.canTurnOff(screens[0]) && model.canTurnOff(screens[1]))
        check("A display that's off can't be turned off again", !model.canTurnOff(screens[2]))
        model.simulate(displays: screens, settings: [:], powerOff: ["b": .disabled, "c": .blackout])
        check("The last display on can't be turned off", !model.canTurnOff(screens[0]))
        let reloaded = AppModel(live: false, defaults: UserDefaults(suiteName: suite)!)
        check("Turned-off displays are saved, to turn them back on after a crash", reloaded.powerOff == ["b": .disabled, "c": .blackout])
        UserDefaults().removePersistentDomain(forName: suite)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    /// `LongoDisplay --diagnose`: what this Mac's displays look like to the app (for bug reports).
    static var isDiagnoseRequested: Bool { CommandLine.arguments.contains("--diagnose") }

    @MainActor
    static func diagnoseAndExit() {
        let engine = DisplayEngine()
        engine.refresh()
        for display in engine.displays {
            let brightness = DisplayServices.brightness(display.id).map { String(format: "%.0f%%", $0 * 100) } ?? "n/a"
            print("\(display.name) [\(display.isBuiltin ? "built-in" : "external")] \(display.sizeLabel)"
                  + " · control: \(display.method.rawValue) · macOS brightness: \(brightness) · id \(display.key)"
                  + (display.method == .ddc ? " · " + engine.ddcReport(display) : ""))
        }
        if engine.displays.isEmpty { print("No active displays") }
        exit(0)
    }

    private static func check(_ name: String, _ ok: Bool) {
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(name)")
    }
}
