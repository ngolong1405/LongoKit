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
        check("Get brightness packet", DDCChannel.readPacket(0x10) == [0x82, 0x01, 0x10, 0xAC])
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x2A, 0x00]
        check("Parse reply: current 42 of 100", DDCChannel.parseReply(reply, code: 0x10).map { $0 == (42, 100) } ?? false)
        check("Reject an error reply", DDCChannel.parseReply([0x6E, 0x88, 0x02, 0x01, 0x10, 0, 0, 0x64, 0, 0x2A, 0], code: 0x10) == nil)
        check("Reject a reply for another control", DDCChannel.parseReply(reply, code: 0x12) == nil)

        // Sync mapping.
        check("Sync: built-in 50% → halfway between 20 and 80", abs(SyncMath.map(builtin: 0.5, minimum: 0.2, maximum: 0.8) - 0.5) < 0.0001)
        check("Sync: built-in 0% → minimum", SyncMath.map(builtin: 0, minimum: 0.3, maximum: 1) == 0.3)
        check("Sync: built-in 100% → maximum", SyncMath.map(builtin: 1, minimum: 0, maximum: 0.6) == 0.6)
        check("Sync: swapped limits still map inside them", SyncMath.map(builtin: 1, minimum: 0.9, maximum: 0.1) == 0.9)
        // A monitor over DDC follows how bright the MacBook looks: lower in the middle, the same at the ends.
        var full = DisplaySettings()
        full.minimum = 0
        full.maximum = 1
        check("Sync: a DDC monitor follows the MacBook's look (50% → 25%), its ends unchanged",
              abs(SyncMath.target(source: 0.5, settings: full, method: .ddc) - 0.25) < 0.0001
              && SyncMath.target(source: 0, settings: full, method: .ddc) == 0 && SyncMath.target(source: 1, settings: full, method: .ddc) == 1)
        check("Sync: software dimming follows straight", abs(SyncMath.target(source: 0.5, settings: full, method: .software) - 0.5) < 0.0001)
        var adjusted = full
        adjusted.syncOffset = 0.2
        check("Sync: the person's adjustment adds on, within 0–100%", abs(SyncMath.target(source: 0.5, settings: adjusted, method: .ddc) - 0.45) < 0.0001
              && SyncMath.target(source: 1, settings: adjusted, method: .ddc) == 1)
        // The time of day, when there's no MacBook display to follow.
        check("Time of day: dark at night, full by day", SyncMath.daylight(hour: 3) == 0 && SyncMath.daylight(hour: 12) == 1 && SyncMath.daylight(hour: 23) == 0)
        check("Time of day: halfway at 7 and at 19", abs(SyncMath.daylight(hour: 7) - 0.5) < 0.0001 && abs(SyncMath.daylight(hour: 19) - 0.5) < 0.0001)
        check("Time of day: brightens through the morning", SyncMath.daylight(hour: 6.5) < SyncMath.daylight(hour: 7.5))
        // Gliding: steady steps to the target, never past it, there in about a second.
        var glided = 0.0, steps = 0, overshoot = false
        while glided != 1 && steps < 100 {
            glided = SyncMath.glide(from: glided, to: 1)
            overshoot = overshoot || glided > 1
            steps += 1
        }
        check("Gliding gets there without overshooting (\(steps) steps)", glided == 1 && !overshoot && steps <= 30)

        // Brightness keys.
        check("Key up from 50% → 9/16", SyncMath.stepped(0.5, up: true) == 9.0 / 16)
        check("Key down stops at 0", SyncMath.stepped(0, up: false) == 0)
        check("Key up stops at 100%", SyncMath.stepped(1, up: true) == 1)

        // One level for brightness and extra dimming.
        var level = DisplaySettings()
        level.setLevel(-0.3)
        check("Below 0% the backlight stays at 0 and the picture dims", level.brightness == 0 && abs(level.extraDim - 0.3) < 0.0001 && abs(level.level + 0.3) < 0.0001)
        level.setLevel(0.4)
        check("Back above 0% the extra dimming is gone", level.brightness == 0.4 && level.extraDim == 0)
        level.setLevel(-5)
        check("Extra dimming stops at its deepest", level.extraDim == DisplaySettings.maxDim)
        check("Key down from 0% goes into extra dimming", SyncMath.stepped(0, up: false, lowest: -DisplaySettings.maxDim) == -1.0 / 16)
        let mixed = try? JSONDecoder().decode(DisplaySettings.self, from: Data(#"{"brightness":0.5,"extraDim":0.3}"#.utf8))
        check("Old dimming above 0% brightness is dropped", mixed?.extraDim == 0)

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
        check("Old settings load with defaults", old?.brightness == 0.4 && old?.maximum == 1 && old?.extraDim == 0 && old?.control == .hardware && old?.volume == nil && old?.syncs == true)

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

        // Sync with a hand on it: a following display set by hand keeps that much on top of its range.
        let syncSuite = "LongoDisplay.selftest.sync"
        UserDefaults().removePersistentDomain(forName: syncSuite)
        let syncing = AppModel(live: false, defaults: UserDefaults(suiteName: syncSuite)!)
        let mac = Display(id: 1, key: "mac", name: "Built-in", isBuiltin: true, method: .native, pixelSize: .zero)
        let monitor = Display(id: 2, key: "lg", name: "LG", isBuiltin: false, method: .ddc, pixelSize: .zero)
        var macSettings = DisplaySettings()
        macSettings.brightness = 0.5
        syncing.simulate(displays: [mac, monitor], settings: ["mac": macSettings, "lg": DisplaySettings()])
        syncing.mode = .sync
        syncing.setLevel(0.6, for: monitor)
        check("In Sync, a display set by hand keeps following, adjusted by that much",
              abs(syncing.settings(for: monitor).syncOffset - 0.35) < 0.0001 && abs(syncing.syncTarget(for: monitor) - 0.6) < 0.0001
              && abs(syncing.settings(for: monitor).level - 0.6) < 0.0001)
        syncing.resetSyncOffset(for: monitor)
        check("…until the adjustment is reset", syncing.settings(for: monitor).syncOffset == 0 && abs(syncing.syncTarget(for: monitor) - 0.25) < 0.0001)
        UserDefaults().removePersistentDomain(forName: syncSuite)

        // Sound outputs: macOS plays through one device at a time; each display is matched to its own.
        let lg = Display(id: 10, key: "lg", name: "LG ULTRAGEAR", isBuiltin: false, method: .ddc, pixelSize: .zero, hasDDC: true)
        let usbC = Display(id: 11, key: "typec", name: "TYPEC", isBuiltin: false, method: .ddc, pixelSize: .zero, hasDDC: true)
        model.simulate(displays: [screens[0], lg, usbC], settings: [:],
                       outputs: [.init(id: 41, name: "MacBook Pro Speakers", isBuiltIn: true), .init(id: 42, name: "LG ULTRAGEAR", isBuiltIn: false)],
                       playing: 41)
        check("The built-in display's sound is the built-in speakers", model.audioOutput(for: screens[0])?.id == 41)
        check("A monitor's sound is the device named after it", model.audioOutput(for: lg)?.id == 42)
        check("Only the device that plays says so", model.isPlaying(screens[0]) == true && model.isPlaying(lg) == false)
        check("A monitor without a sound device shows neither", model.isPlaying(usbC) == nil)

        // Volume: a pause at 80% on the way up, then on to 100%.
        var detent = VolumeDetent()
        let start = Date()
        check("Up to 80% the volume follows the drag", detent.next(from: 0.5, to: 0.75, now: start) == 0.75)
        check("Going past 80% stops there first", detent.next(from: 0.75, to: 0.9, now: start) == 0.8)
        check("…for half a second", detent.next(from: 0.8, to: 0.95, now: start.addingTimeInterval(0.3)) == 0.8)
        check("…then it carries on to 100%", detent.next(from: 0.8, to: 1, now: start.addingTimeInterval(0.6)) == 1)
        check("Above 80%, moving within it isn't held", detent.next(from: 0.9, to: 0.95, now: start.addingTimeInterval(0.7)) == 0.95)
        _ = detent.next(from: 0.9, to: 0.6, now: start.addingTimeInterval(1))
        check("Back below 80%, the next time up stops again", detent.next(from: 0.6, to: 0.9, now: start.addingTimeInterval(1.1)) == 0.8)
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
