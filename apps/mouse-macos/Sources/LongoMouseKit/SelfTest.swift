import AppKit
import LongoKitUI

/// `LongoMouse --selftest` drives the engine with synthetic mouse events and checks which actions it would send.
/// Nothing reaches the system: ActionPerformer reports into a recorder instead.
enum SelfTest {
    static var isRequested: Bool { CommandLine.arguments.contains("--selftest") }

    private static var recorded: [String] = []
    private static var failures = 0
    private static let engine = MouseEngine.shared
    /// Buttons the synthetic events hold down, standing in for the hardware state.
    private static var held: Set<Int> = []

    @MainActor
    static func runAndExit() {
        ActionPerformer.recorder = { recorded.append($0) }
        engine.isButtonDown = { held.contains($0) }
        engine.isEnabled = true
        engine.scroll = ScrollSettings()
        engine.scroll.inertia = false

        let b4 = Trigger(button: 3, modifiers: [])
        let b5 = Trigger(button: 4, modifiers: [])

        check("Click runs its action", [bind(b4, .click, .spaceLeft)], expect: ["key 123⌃"]) {
            press(3); release(3)
        }
        check("Click is swallowed (the original button press doesn't reach apps)", [bind(b4, .click, .back)], expect: ["key 33⌘"]) {
            assertSwallowed(press(3), true)
            assertSwallowed(release(3), true)
        }
        check("Unbound button passes through untouched", [bind(b4, .click, .back)], expect: []) {
            assertSwallowed(press(5), false)
            assertSwallowed(release(5), false)
        }
        check("Hold runs after 0.4 s and suppresses the click", [bind(b4, .click, .spaceLeft), bind(b4, .hold, .appExpose)],
              expect: ["key 125⌃"]) {
            press(3); wait(0.6); release(3)
        }
        check("Quick press still clicks when a hold is also bound", [bind(b4, .click, .spaceLeft), bind(b4, .hold, .appExpose)],
              expect: ["key 123⌃"]) {
            press(3); wait(0.1); release(3)
        }
        check("Hold-only button replays its normal click on a quick press", [bind(b4, .hold, .appExpose)], expect: ["click 3"]) {
            press(3); release(3)
        }
        check("A button can triple-click the left button", [bind(b4, .click, .primaryTripleClick)], expect: ["click 0 ×3"]) {
            press(3); release(3)
        }
        check("…or double-click the right one", [bind(b4, .click, .secondaryDoubleClick)], expect: ["click 1 ×2"]) {
            press(3); release(3)
        }
        let older = try? JSONDecoder().decode(ScrollSettings.self, from: Data(#"{"speed":1.2}"#.utf8))
        report("Sideways scrolling and back/forward are on by default, also for older settings",
               ScrollSettings().horizontalSwipe && ScrollSettings().swipeNavigation
               && older?.horizontalSwipe == true && older?.swipeNavigation == true, "older: \(String(describing: older))")
        engine.clickGuard = 0.06
        check("Double-click fix: a bouncing press stays one click", [], expect: ["release 0"]) {
            assertSwallowed(press(0), false); assertSwallowed(release(0), true)
            assertSwallowed(press(0), true); assertSwallowed(release(0), true)
            wait(0.15)
        }
        check("Double-click fix: a real double click still gets through", [], expect: ["release 0", "release 0"]) {
            assertSwallowed(press(0), false); release(0); wait(0.15)
            assertSwallowed(press(0), false); release(0); wait(0.15)
        }
        check("Double-click fix: a held press can still drag", [], expect: ["release 1"]) {
            press(1); release(1); assertSwallowed(press(1), true); wait(0.2); release(1); wait(0.15)
        }
        engine.clickGuard = nil
        check("Double-click fix off: releases pass straight through", [], expect: []) {
            press(0); assertSwallowed(release(0), false)
        }
        check("Double click runs the double action", [bind(b4, .click, .spaceLeft), bind(b4, .doubleClick, .showDesktop)],
              expect: ["key 103"]) {
            press(3); release(3); wait(0.08); press(3); release(3); wait(NSEvent.doubleClickInterval + 0.2)
        }
        check("Single click waits out the double-click interval", [bind(b4, .click, .spaceLeft), bind(b4, .doubleClick, .showDesktop)],
              expect: ["key 123⌃"]) {
            press(3); release(3); wait(NSEvent.doubleClickInterval + 0.2)
        }
        check("Drag right switches space (once) and suppresses the click", [bind(b5, .click, .spaceRight), bind(b5, .drag, .dragSpaces)],
              expect: ["key 123⌃"]) {
            press(4); drag(4, dx: 30); drag(4, dx: 30); drag(4, dx: 30); release(4)
        }
        check("Drag left switches the other way", [bind(b5, .drag, .dragSpaces)], expect: ["key 124⌃"]) {
            press(4); drag(4, dx: -60); release(4)
        }
        check("Drag up opens Mission Control", [bind(b5, .drag, .dragMissionControl)], expect: ["missionControl"]) {
            press(4); drag(4, dy: -60); release(4)
        }
        check("Drag to scroll pans content", [bind(b5, .drag, .dragScroll)], expect: ["scroll", "scroll"]) {
            press(4); drag(4, dy: 5); drag(4, dy: 5); release(4)
        }
        check("Small jitter while pressing still counts as a click", [bind(b5, .click, .spaceRight), bind(b5, .drag, .dragSpaces)],
              expect: ["key 124⌃"]) {
            press(4); drag(4, dx: 3); release(4)
        }
        check("Click + scroll zooms and suppresses the click", [bind(b4, .click, .back), bind(b4, .scroll, .scrollZoom)],
              expect: ["key 24⌘", "key 27⌘"]) {
            press(3); scroll(1); scroll(-1); release(3)
        }
        check("Modified left click can be remapped", [bind(Trigger(button: 0, modifiers: .option), .click, .missionControl)],
              expect: ["missionControl"]) {
            press(0, flags: .maskAlternate); release(0)
        }
        check("Plain left click always passes through", [bind(Trigger(button: 0, modifiers: .option), .click, .missionControl)],
              expect: []) {
            assertSwallowed(press(0), false)
            assertSwallowed(release(0), false)
        }
        check("Modifier must match the binding", [bind(Trigger(button: 3, modifiers: .command), .click, .back)], expect: []) {
            assertSwallowed(press(3), false)
            release(3)
        }
        check("Shortcut action sends the recorded keys",
              [MouseBinding(trigger: b4, action: .shortcut, shortcut: KeyShortcut(keyCode: 21, modifiers: [.command, .shift], keyName: "4"))],
              expect: ["key 21⇧⌘"]) {
            press(3); release(3)
        }
        check("Media key action", [MouseBinding(trigger: b4, action: .mediaKey, mediaKey: .playPause)], expect: ["media 16"]) {
            press(3); release(3)
        }
        check("Disabled engine passes everything through", [bind(b4, .click, .back)], expect: []) {
            engine.isEnabled = false
            assertSwallowed(press(3), false)
            release(3)
            engine.isEnabled = true
        }

        // Safety: nothing stays stuck.
        check("Held button still turns the wheel into its action", [bind(b4, .scroll, .scrollZoom)], expect: ["key 24⌘"]) {
            press(3); wait(0.6); scroll(1); release(3)
        }
        check("A button released unseen stops hijacking the wheel", [bind(b4, .scroll, .scrollZoom)], expect: []) {
            press(3); wait(0.6)
            held.remove(3) // its mouse-up never reached the tap
            assertSwallowed(scroll(1), false)
        }
        check("Pausing mid-hold cancels the hold", [bind(b4, .hold, .missionControl)], expect: []) {
            press(3)
            engine.isEnabled = false
            wait(0.6)
            engine.isEnabled = true
            release(3)
        }
        check("macOS pausing the tap drops half-seen gestures", [bind(b4, .hold, .missionControl)], expect: []) {
            press(3)
            _ = engine.process(.tapDisabledByTimeout, mouseEvent(.otherMouseDown, 3))
            wait(0.6)
            held.remove(3)
        }
        expectGlideCap()

        // Scroll wheel reshaping.
        engine.systemNaturalScrolling = true
        expectScroll("Wheel is untouched by default", ScrollSettings(), delta: 1, expected: 1)
        var classic = ScrollSettings()
        classic.invertDirection = true
        expectScroll("Classic direction flips the wheel when macOS is natural", classic, delta: 1, expected: -1)
        engine.systemNaturalScrolling = false
        expectScroll("Natural direction flips the wheel when macOS is classic", ScrollSettings(), delta: 1, expected: -1)
        expectScroll("Classic direction leaves the wheel alone when macOS is classic", classic, delta: 1, expected: 1)
        engine.systemNaturalScrolling = true
        expectScrollPhase("Trackpad gestures are left alone", classic)
        expectScroll("Smooth (continuous) wheels are reshaped too", classic, delta: 1, expected: -1, continuous: true)
        var fast = ScrollSettings()
        fast.speed = 2
        expectGlide()
        expectScroll("Scroll speed scales the wheel", fast, delta: 1, expected: 2)
        expectSideways()

        // Recording classifies each gesture.
        expectCapture("Recording: click", .click) { press(3); release(3); wait(NSEvent.doubleClickInterval + 0.2) }
        expectCapture("Recording: double click", .doubleClick) { press(3); release(3); wait(0.08); press(3); release(3) }
        expectCapture("Recording: hold", .hold) { press(3); wait(0.6); release(3) }
        expectCapture("Recording: drag", .drag) { press(3); drag(3, dx: 20); release(3) }
        expectCapture("Recording: click and scroll", .scroll) { press(3); scroll(1); release(3) }

        // Mice that send a side button as a key combo (UGREEN: ⌃→).
        checkMouseKeys()

        // Per-mouse layouts.
        checkProfiles()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Cases

    private static func check(_ name: String, _ bindings: [MouseBinding], expect: [String], _ steps: () -> Void) {
        engine.resetState()
        held = []
        engine.update(bindings)
        recorded = []
        steps()
        wait(0.05)
        report(name, recorded == expect, "expected \(expect), got \(recorded)")
    }

    private static func expectScrollPhase(_ name: String, _ settings: ScrollSettings) {
        engine.resetState()
        engine.update([])
        engine.scroll = settings
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 10, wheel2: 0, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2) // changed
        _ = engine.process(.scrollWheel, event)
        let result = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        report(name, result == 10, "expected 10, got \(result)")
        engine.scroll = ScrollSettings()
    }

    /// ⇧ + wheel turns sideways; ⌃⇧ + wheel goes back / forward a page; both can be switched off.
    private static func expectSideways() {
        func wheel(_ flags: CGEventFlags) -> CGEvent {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)!
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
            event.flags = flags
            return event
        }
        engine.resetState()
        engine.update([])
        engine.systemNaturalScrolling = false
        engine.scroll = ScrollSettings()
        engine.scroll.inertia = false
        engine.scroll.invertDirection = true // classic on a classic Mac: the wheel isn't flipped

        var event = wheel(.maskShift)
        let passed = !engine.process(.scrollWheel, event)
        report("⇧ + wheel scrolls sideways", passed && event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 0
               && event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 1,
               "axis1 \(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)), axis2 \(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))")

        engine.scroll.horizontalSwipe = false
        event = wheel(.maskShift)
        _ = engine.process(.scrollWheel, event)
        report("⇧ + wheel left alone when switched off", event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 1, "")

        recorded = []
        let swallowed = engine.process(.scrollWheel, wheel([.maskShift, .maskControl]))
        report("⌃⇧ + wheel up goes back a page", swallowed && recorded == ["key 33⌘"], "got \(recorded)")
        engine.scroll.swipeNavigation = false
        recorded = []
        _ = engine.process(.scrollWheel, wheel([.maskShift, .maskControl]))
        report("⌃⇧ + wheel does nothing special when switched off", recorded.isEmpty, "got \(recorded)")

        engine.systemNaturalScrolling = true
        engine.scroll = ScrollSettings()
        engine.scroll.inertia = false
    }

    private static func expectScroll(_ name: String, _ settings: ScrollSettings, delta: Int32, expected: Int64,
                                     continuous: Bool = false) {
        engine.resetState()
        engine.update([])
        engine.scroll = settings
        engine.scroll.inertia = false
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        let fixedBefore = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        _ = engine.process(.scrollWheel, event)
        let result = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        // Apps read the fixed-point delta, so it must follow the line delta.
        let fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let fixedOK = abs(fixed - fixedBefore * Double(expected) / Double(delta)) < 0.01
        report(name, result == expected && fixedOK,
               "expected \(expected), got \(result) (fixed-point \(fixedBefore) → \(fixed))")
        engine.scroll = ScrollSettings()
        engine.scroll.inertia = false
    }

    /// With smooth scrolling on, a notch is swallowed and replayed as an eased series of small scrolls.
    private static func expectGlide() {
        engine.resetState()
        engine.update([])
        engine.scroll = ScrollSettings()
        recorded = []
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
        let swallowed = engine.process(.scrollWheel, event)
        wait(0.1)
        let early = recorded.count
        wait(1.5)
        let settled = recorded.count
        wait(0.3)
        report("Smooth scrolling animates a notch, then settles",
               // Timing varies between machines (CI runners are slower), so only ask that it starts, keeps going, then stops.
               swallowed && early >= 1 && settled > early && recorded.count == settled,
               "swallowed \(swallowed), posted \(early) then \(settled) then \(recorded.count)")
        engine.resetState()
        engine.scroll.inertia = false
    }

    /// Spinning the wheel hard can't queue up minutes of smooth scrolling.
    private static func expectGlideCap() {
        engine.resetState()
        engine.update([])
        engine.scroll = ScrollSettings()
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 2000, wheel2: 0, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
        _ = engine.process(.scrollWheel, event)
        report("Smooth scrolling never queues more than \(Int(MouseEngine.maxGlide)) px",
               engine.pendingGlide > 0 && engine.pendingGlide <= MouseEngine.maxGlide, "pending \(engine.pendingGlide)")
        engine.resetState()
        engine.scroll.inertia = false
    }

    /// ⌃→ from the mouse's keyboard interface: HID usage 0x4F with Left Control (bit 0).
    private static let arrowUsage = 0x4F
    private static var arrowButton: Int { MouseKeys.button(usage: arrowUsage, modifiers: 1) }

    private static func keyEvent(_ down: Bool) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: down)!
        event.flags = .maskControl
        return event
    }

    private static func checkMouseKeys() {
        // Listening: the report arrives first, then the key events, which must not reach apps.
        engine.resetState()
        engine.update([])
        var captured: [Trigger] = []
        engine.captureHandler = { trigger, _ in captured.append(trigger) }
        engine.mouseKey(usage: arrowUsage, modifiers: 1, down: true)
        let downSwallowed = engine.process(.keyDown, keyEvent(true))
        engine.mouseKey(usage: arrowUsage, modifiers: 1, down: false)
        let upSwallowed = engine.process(.keyUp, keyEvent(false))
        wait(NSEvent.doubleClickInterval + 0.2)
        engine.captureHandler = nil
        report("Key-combo button is captured and its keys swallowed",
               captured.map(\.button) == [arrowButton] && downSwallowed && upSwallowed,
               "captured \(captured.map(\.title)), swallowed \(downSwallowed)/\(upSwallowed)")

        // Mapped, with the key event reaching the tap before the mouse's report.
        let trigger = Trigger(button: arrowButton, modifiers: [])
        check("Key-combo button runs its action even when the key event comes first",
              [bind(trigger, .click, .missionControl)], expect: ["missionControl"]) {
            assertSwallowed(engine.process(.keyDown, keyEvent(true)), true)
            engine.mouseKey(usage: arrowUsage, modifiers: 1, down: true)
            engine.mouseKey(usage: arrowUsage, modifiers: 1, down: false)
            assertSwallowed(engine.process(.keyUp, keyEvent(false)), true)
        }

        // The same keys typed on a keyboard: held a moment, then let through unchanged.
        check("The same keys from a keyboard still go through", [bind(trigger, .click, .missionControl)],
              expect: ["key passed 124", "key passed 124"]) {
            _ = engine.process(.keyDown, keyEvent(true))
            _ = engine.process(.keyUp, keyEvent(false))
            wait(0.15)
        }

        // Not mapped and not listening: the mouse's keys keep doing what they did (switch Spaces).
        check("Unmapped key-combo button keeps its keys", [], expect: []) {
            engine.mouseKey(usage: arrowUsage, modifiers: 1, down: true)
            assertSwallowed(engine.process(.keyDown, keyEvent(true)), false)
            engine.mouseKey(usage: arrowUsage, modifiers: 1, down: false)
            assertSwallowed(engine.process(.keyUp, keyEvent(false)), false)
        }
    }

    private static func expectCapture(_ name: String, _ expected: ClickType, _ steps: () -> Void) {
        engine.resetState()
        engine.update([])
        var captured: [ClickType] = []
        engine.captureHandler = { _, type in captured.append(type) }
        steps()
        wait(0.1)
        engine.captureHandler = nil
        report(name, captured == [expected], "expected [\(expected)], got \(captured)")
    }

    /// The engine must follow the layout of the mouse in use, or the shared one.
    @MainActor
    private static func checkProfiles() {
        let suite = "MouseMapper.selftest"
        UserDefaults().removePersistentDomain(forName: suite)
        let model = AppModel(startsEngine: false, defaults: UserDefaults(suiteName: suite)!)
        let trackball = MouseDevice(id: "t", product: "Trackball", manufacturer: "", transport: "Bluetooth",
                                    vendorID: 1, productID: 1, battery: nil)
        let other = MouseDevice(id: "o", product: "Other", manufacturer: "", transport: "USB",
                                vendorID: 2, productID: 2, battery: nil)
        model.bindings = [bind(Trigger(button: 3, modifiers: []), .click, .back)]
        model.simulate(devices: [trackball, other], active: "t")
        model.setIndependent("t", true)
        model.editingDeviceID = "t"
        model.assign(.missionControl, to: model.editing[0].id, trigger: Trigger(button: 3, modifiers: []), clickType: .click)

        report("Profiles: mouse with own buttons uses them", engine.bindings.first?.action == .missionControl,
               "engine has \(engine.bindings.map(\.action))")
        model.simulate(devices: [trackball, other], active: "o")
        report("Profiles: switching mouse switches layout", engine.bindings.first?.action == .back,
               "engine has \(engine.bindings.map(\.action))")
        model.setOwnScroll("t", true)
        model.editingDeviceID = "t"
        model.editingScroll.invertDirection = true
        model.simulate(devices: [trackball, other], active: "t")
        report("Profiles: mouse with own scrolling uses it", engine.scroll.invertDirection && !model.scroll.invertDirection,
               "engine \(engine.scroll.invertDirection), shared \(model.scroll.invertDirection)")
        model.simulate(devices: [trackball, other], active: "o")
        report("Profiles: other mouse keeps the shared scrolling", !engine.scroll.invertDirection,
               "engine \(engine.scroll.invertDirection)")
        model.autoSwitchProfiles = false
        model.simulate(devices: [trackball, other], active: "t")
        report("Profiles: auto-switch off always uses the shared layout", engine.bindings.first?.action == .back,
               "engine has \(engine.bindings.map(\.action))")
        UserDefaults().removePersistentDomain(forName: suite)
    }

    // MARK: - Event helpers

    private static func bind(_ trigger: Trigger, _ type: ClickType, _ action: ActionKind) -> MouseBinding {
        MouseBinding(trigger: trigger, clickType: type, action: action)
    }

    @discardableResult
    private static func press(_ button: Int, flags: CGEventFlags = []) -> Bool {
        held.insert(button)
        return send(button == 0 ? .leftMouseDown : button == 1 ? .rightMouseDown : .otherMouseDown, button, flags: flags)
    }

    @discardableResult
    private static func release(_ button: Int) -> Bool {
        held.remove(button)
        return send(button == 0 ? .leftMouseUp : button == 1 ? .rightMouseUp : .otherMouseUp, button)
    }

    private static func drag(_ button: Int, dx: Int64 = 0, dy: Int64 = 0) {
        let event = mouseEvent(button == 0 ? .leftMouseDragged : .otherMouseDragged, button)
        event.setIntegerValueField(.mouseEventDeltaX, value: dx)
        event.setIntegerValueField(.mouseEventDeltaY, value: dy)
        _ = engine.process(button == 0 ? .leftMouseDragged : .otherMouseDragged, event)
    }

    @discardableResult
    private static func scroll(_ lines: Int32) -> Bool {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)!
        return engine.process(.scrollWheel, event)
    }

    private static func send(_ type: CGEventType, _ button: Int, flags: CGEventFlags = []) -> Bool {
        let event = mouseEvent(type, button)
        event.flags = flags
        return engine.process(type, event)
    }

    private static func mouseEvent(_ type: CGEventType, _ button: Int) -> CGEvent {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero,
                            mouseButton: CGMouseButton(rawValue: UInt32(min(button, 2))) ?? .center)!
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        return event
    }

    /// Lets the engine's hold and double-click timers fire.
    private static func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func assertSwallowed(_ swallowed: Bool, _ expected: Bool) {
        if swallowed != expected {
            report("  event swallowed == \(expected)", false, "it was \(swallowed)")
        }
    }

    private static func report(_ name: String, _ ok: Bool, _ detail: String) {
        if ok {
            print("PASS  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name) — \(detail)")
        }
    }
}
