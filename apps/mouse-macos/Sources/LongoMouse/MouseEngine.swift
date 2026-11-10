import AppKit
import ApplicationServices
import Carbon.HIToolbox
import LongoKitUI

/// Intercepts extra mouse buttons (middle and up) and the scroll wheel system-wide through a CGEventTap.
/// The tap runs on the main run loop, so all state here is only touched from the main thread.
final class MouseEngine {
    static let shared = MouseEngine()

    var isEnabled = true {
        // Paused mid-gesture: drop it, so no hold or click fires afterwards.
        didSet { if !isEnabled { forgetGestures() } }
    }
    var scroll = ScrollSettings()
    /// macOS "Natural scrolling" (System Settings › Mouse/Trackpad), which the wheel already follows before we see it.
    var systemNaturalScrolling = MouseEngine.readSystemNaturalScrolling()
    private(set) var bindings: [MouseBinding] = []

    /// While set, extra-button gestures are classified and delivered here instead of being remapped.
    var captureHandler: ((Trigger, ClickType) -> Void)? {
        didSet { updateKeyTap() }
    }

    /// Double-click fix for a worn left/right button that chatters (one press arrives as two clicks): a release is
    /// held this long, and a press arriving meanwhile is the same press bouncing, so both are dropped. Nil is off.
    var clickGuard: TimeInterval? {
        didSet { if clickGuard == nil { releaseHeldUps() } }
    }
    private var heldUps: [Int: (event: CGEvent, work: DispatchWorkItem)] = [:]
    /// The click state of each button's last press, given to its delayed release.
    private var pressClickState: [Int: Int64] = [:]

    private struct Press {
        var trigger: Trigger
        var capturing: Bool
        /// A hold, drag or scroll already fired for this press, so releasing it must not click.
        var used = false
        var dragX = 0.0
        var dragY = 0.0
        var holdTimer: DispatchWorkItem?
        var started = Date()
    }

    private var tap: CFMachPort?
    /// A second tap, on key events, that only exists while listening or while a button that sends a key combo
    /// is mapped. Otherwise typing never passes through this app.
    private var keyTap: CFMachPort?
    private var keyTapSource: CFRunLoopSource?
    private var presses: [Int: Press] = [:]
    private var pendingClicks: [Int: DispatchWorkItem] = [:]
    private var pendingCapture: (button: Int, work: DispatchWorkItem)?
    /// Buttons that send key combos (see MouseKeys), by key code, while the mouse reports them held;
    /// `swallowed` when the press is listened for or mapped, so the key events must not reach apps.
    private var keyButtonsDown: [UInt16: (button: Int, swallowed: Bool)] = [:]
    /// Key presses held back until the mouse's own report says whether they came from the mouse.
    private var heldKeys: [UInt16: (down: CGEvent, up: CGEvent?, work: DispatchWorkItem)] = [:]
    /// Key codes whose press was swallowed, so its auto-repeats and release are swallowed too.
    private var swallowedKeys: Set<UInt16> = []
    /// Key codes some mouse has sent before. Only these (or any key while listening) wait for the mouse's report.
    var mouseKeyCodes: Set<UInt16> = []
    /// Called when a mouse sends a key code for the first time, to remember it.
    var onNewMouseKeyCode: ((UInt16) -> Void)?
    /// How long a key press may wait for the mouse's report before it goes through as a normal key.
    private static let mouseKeyWait = 0.06
    private var lastSpaceSwitch = Date.distantPast
    private var lastPageSwipe = Date.distantPast
    /// Smooth scrolling: pixels still to scroll on each axis, and the fractions not yet posted.
    private var glide = (vertical: 0.0, horizontal: 0.0, carryV: 0.0, carryH: 0.0)
    private var glideTimer: Timer?
    private var lastGlideFrame = Date()

    /// Pixels one wheel line scrolls when smooth scrolling animates it (about what browsers use for a line).
    private static let pixelsPerLine = 40.0

    private static let holdDelay = 0.4
    private static let dragThreshold = 40.0
    private static let captureDragThreshold = 12.0
    /// Smooth scrolling never has more than this left to scroll (pixels per axis), however fast the wheel spins.
    static let maxGlide = 4000.0

    /// Whether a button is physically held, from the hardware state (it doesn't see what the tap swallows).
    var isButtonDown: (Int) -> Bool = { button in
        CGMouseButton(rawValue: UInt32(button)).map { CGEventSource.buttonState(.hidSystemState, button: $0) } ?? true
    }

    var isRunning: Bool { tap != nil }

    private init() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("SwipeScrollDirectionDidChangeNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.systemNaturalScrolling = MouseEngine.readSystemNaturalScrolling()
        }
    }

    static func readSystemNaturalScrolling() -> Bool {
        let key = "com.apple.swipescrolldirection" as CFString
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return (CFPreferencesCopyAppValue(key, kCFPreferencesAnyApplication) as? Bool) ?? true
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func update(_ bindings: [MouseBinding]) {
        self.bindings = bindings
        updateKeyTap()
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged,
                                    .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                    .rightMouseDown, .rightMouseUp, .rightMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let engine = Unmanaged<MouseEngine>.fromOpaque(refcon!).takeUnretainedValue()
                return engine.handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        updateKeyTap()
        return true
    }

    private func updateKeyTap() {
        let needed = tap != nil && (captureHandler != nil || bindings.contains { MouseKeys.isKeyButton($0.trigger.button) })
        guard needed != (keyTap != nil) else { return }
        if needed {
            let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            guard let keyTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                callback: { _, type, event, refcon in
                    Unmanaged<MouseEngine>.fromOpaque(refcon!).takeUnretainedValue().handle(type, event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else { return }
            let source = CFMachPortCreateRunLoopSource(nil, keyTap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: keyTap, enable: true)
            self.keyTap = keyTap
            keyTapSource = source
        } else {
            if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: false); CFMachPortInvalidate(keyTap) }
            if let keyTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), keyTapSource, .commonModes) }
            keyTap = nil
            keyTapSource = nil
            // Keys still waiting for the mouse's report go through as they were.
            for held in heldKeys.values {
                held.work.cancel()
                Self.repost(held.down)
                held.up.map(Self.repost)
            }
            heldKeys.removeAll()
            swallowedKeys.removeAll()
        }
    }

    // MARK: - Event handling

    /// Self-test entry point: runs an event through the tap logic; true when it was swallowed.
    func process(_ type: CGEventType, _ event: CGEvent) -> Bool {
        handle(type, event) == nil
    }

    /// Self-test only: forget any half-finished gesture between cases.
    func resetState() {
        forgetGestures()
        heldKeys.values.forEach { $0.work.cancel() }
        heldKeys.removeAll()
        keyButtonsDown.removeAll()
        swallowedKeys.removeAll()
        pendingCapture?.work.cancel()
        pendingCapture = nil
    }

    /// Self-test only: pixels smooth scrolling still has to scroll vertically.
    var pendingGlide: Double { abs(glide.vertical) }

    /// Drops held buttons, waiting clicks and any glide in progress.
    private func forgetGestures() {
        releaseHeldUps()
        presses.values.forEach { $0.holdTimer?.cancel() }
        presses.removeAll()
        pendingClicks.values.forEach { $0.cancel() }
        pendingClicks.removeAll()
        stopGlide()
    }

    /// A button released while the tap was off (macOS pauses a slow tap) never sends us its mouse-up. Without this
    /// the wheel would stay hijacked by a "held" button that isn't, e.g. zooming on every scroll.
    private func dropStalePresses() {
        for (button, press) in presses where Date().timeIntervalSince(press.started) > 0.5 && !isButtonDown(button) {
            press.holdTimer?.cancel()
            presses.removeValue(forKey: button)
        }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Events were missed while off; start clean rather than finish a gesture half-seen.
            forgetGestures()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == ActionPerformer.syntheticTag { return pass }
        if type == .scrollWheel { return scrollWheel(event) ? nil : pass }
        if type == .keyDown || type == .keyUp { return key(type == .keyDown, event) ? nil : pass }

        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        switch type {
        case .otherMouseDown, .leftMouseDown, .rightMouseDown:
            stopGlide() // a click means the user has arrived
            dropStalePresses()
            let modifiers = Modifiers(event.flags)
            // Plain left/right clicks are how you use the Mac (and this app); only modified ones can be remapped.
            if button < 2 && modifiers.isEmpty {
                if guardPress(button) { return nil }
                pressClickState[button] = event.getIntegerValueField(.mouseEventClickState)
                return pass
            }
            return mouseDown(button, modifiers) ? nil : pass
        case .otherMouseUp, .leftMouseUp, .rightMouseUp:
            if mouseUp(button) { return nil }
            return button < 2 && guardRelease(button, event) ? nil : pass
        case .otherMouseDragged, .leftMouseDragged, .rightMouseDragged:
            return mouseDragged(button, event) ? nil : pass
        default:
            return pass
        }
    }

    /// Returns true when the event should be swallowed.
    private func mouseDown(_ button: Int, _ modifiers: Modifiers) -> Bool {
        let trigger = Trigger(button: button, modifiers: modifiers)

        if captureHandler != nil {
            // The second press of a double click while recording.
            if let pending = pendingCapture, pending.button == button {
                pending.work.cancel()
                pendingCapture = nil
                presses[button] = Press(trigger: trigger, capturing: true, used: true)
                deliverCapture(trigger, .doubleClick)
                return true
            }
            var press = Press(trigger: trigger, capturing: true)
            press.holdTimer = schedule(Self.holdDelay) { [weak self] in
                guard let self, var p = self.presses[button], !p.used else { return }
                p.used = true
                self.presses[button] = p
                self.deliverCapture(trigger, .hold)
            }
            presses[button] = press
            return true
        }

        guard isEnabled, bindings.contains(where: { matches($0, trigger) }) else { return false }
        var press = Press(trigger: trigger, capturing: false)
        if let hold = binding(trigger, .hold) {
            press.holdTimer = schedule(Self.holdDelay) { [weak self] in
                guard let self, var p = self.presses[button], !p.used else { return }
                p.used = true
                self.presses[button] = p
                self.pendingClicks.removeValue(forKey: button)?.cancel()
                ActionPerformer.perform(hold)
            }
        }
        presses[button] = press
        return true
    }

    private func mouseUp(_ button: Int) -> Bool {
        guard let press = presses.removeValue(forKey: button) else { return false }
        press.holdTimer?.cancel()
        if press.used { return true }
        let trigger = press.trigger

        if press.capturing {
            // Wait out the double-click interval before calling it a single click.
            let work = schedule(NSEvent.doubleClickInterval) { [weak self] in
                self?.pendingCapture = nil
                self?.deliverCapture(trigger, .click)
            }
            pendingCapture = (button, work)
            return true
        }

        let click = binding(trigger, .click)
        guard let double = binding(trigger, .doubleClick) else {
            fire(click, button)
            return true
        }

        // A double-click binding exists, so a single click has to wait out the double-click interval.
        if let pending = pendingClicks.removeValue(forKey: button) {
            pending.cancel()
            ActionPerformer.perform(double)
        } else {
            pendingClicks[button] = schedule(NSEvent.doubleClickInterval) { [weak self] in
                self?.pendingClicks.removeValue(forKey: button)
                self?.fire(click, button)
            }
        }
        return true
    }

    private func mouseDragged(_ button: Int, _ event: CGEvent) -> Bool {
        guard var press = presses[button] else { return false }
        defer { presses[button] = press }
        let dx = Double(event.getIntegerValueField(.mouseEventDeltaX))
        let dy = Double(event.getIntegerValueField(.mouseEventDeltaY))
        press.dragX += dx
        press.dragY += dy

        if press.capturing {
            if !press.used, hypot(press.dragX, press.dragY) > Self.captureDragThreshold {
                press.used = true
                press.holdTimer?.cancel()
                deliverCapture(press.trigger, .drag)
            }
            return true
        }

        guard let drag = binding(press.trigger, .drag) else { return true }
        switch drag.action {
        case .dragScroll:
            press.used = true
            press.holdTimer?.cancel()
            // Grab-and-pan: dragging down pulls the content down, like a trackpad.
            ActionPerformer.postScroll(dx: Int32(dx), dy: Int32(dy))
        case .dragSpaces, .dragMissionControl:
            guard !press.used, hypot(press.dragX, press.dragY) > Self.dragThreshold else { break }
            let horizontal = abs(press.dragX) >= abs(press.dragY)
            if drag.action == .dragSpaces, horizontal {
                ActionPerformer.postKey(press.dragX > 0 ? 123 : 124, [.control])
            } else if drag.action == .dragMissionControl, !horizontal {
                if press.dragY < 0 {
                    ActionPerformer.openMissionControl()
                } else {
                    ActionPerformer.postKey(125, [.control])
                }
            } else {
                break
            }
            press.used = true
            press.holdTimer?.cancel()
        default:
            break
        }
        return true
    }

    private func scrollWheel(_ event: CGEvent) -> Bool {
        dropStalePresses()
        // A held button with a scroll binding turns the wheel into that action.
        for (button, var press) in presses {
            if press.capturing {
                if !press.used {
                    press.used = true
                    press.holdTimer?.cancel()
                    presses[button] = press
                    deliverCapture(press.trigger, .scroll)
                }
                return true
            }
            guard let action = binding(press.trigger, .scroll)?.action else { continue }
            press.used = true
            press.holdTimer?.cancel()
            presses[button] = press

            let delta = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            switch action {
            case .scrollZoom:
                if delta != 0 { ActionPerformer.postKey(delta > 0 ? 24 : 27, [.command]) } // ⌘= / ⌘-
            case .scrollSpaces:
                if delta != 0, Date().timeIntervalSince(lastSpaceSwitch) > 0.35 {
                    lastSpaceSwitch = Date()
                    ActionPerformer.postKey(delta > 0 ? 123 : 124, [.control])
                }
            case .scrollHorizontal:
                swapAxes(event)
                return false
            default:
                break
            }
            return true
        }

        // Otherwise only reshape mouse wheels. Trackpads and Magic Mouse scroll in gesture phases;
        // high-resolution wheels are continuous too but carry no phase.
        let gesture = event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0
            || event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0
        guard isEnabled, !gesture else {
            stopGlide()
            return false
        }
        let shift = event.flags.contains(.maskShift)
        // ⌃⇧ + wheel: back (wheel up) or forward (wheel down) a page, once per flick of the wheel.
        if scroll.swipeNavigation, shift, event.flags.contains(.maskControl) {
            let raw = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            // The wheel arrives following macOS's direction setting; undo that to know which way it turned.
            let wheelUp = (systemNaturalScrolling ? -raw : raw) > 0
            if raw != 0, Date().timeIntervalSince(lastPageSwipe) > 0.35 {
                lastPageSwipe = Date()
                ActionPerformer.postKey(wheelUp ? 33 : 30, [.command]) // ⌘[ / ⌘]
            }
            return true
        }
        // ⇧ + wheel: sideways. The vertical turn becomes horizontal before the rest applies to it.
        if scroll.horizontalSwipe, shift, event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) == 0 {
            swapAxes(event)
        }

        // The wheel arrives already following the system setting; flip it when the chosen direction differs.
        let wantsNatural = !scroll.invertDirection
        var factor = wantsNatural == systemNaturalScrolling ? 1.0 : -1.0
        if scroll.smoothEnabled {
            factor *= scroll.speed
            if event.flags.contains(.maskAlternate) {
                factor *= 0.25 // Precision Scroll
            } else if event.flags.contains(.maskCommand) {
                factor *= 4 // Turbo Scroll
            }
        }
        // Smooth scrolling animates notched wheels; high-resolution wheels are smooth already.
        let notched = event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0
        if scroll.inertia && notched {
            addGlide(vertical: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) * factor,
                     horizontal: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) * factor)
            return true
        }
        if factor != 1 { scale(event, by: factor) }
        return false
    }

    /// Instead of jumping a whole notch at once, the distance is scrolled over a few frames,
    /// fast at first and easing out. Notches that arrive mid-animation extend it.
    private func addGlide(vertical: Double, horizontal: Double) {
        // Turning the wheel back cancels what's left in the old direction.
        if vertical != 0, (glide.vertical > 0) != (vertical > 0) { glide.vertical = 0 }
        if horizontal != 0, (glide.horizontal > 0) != (horizontal > 0) { glide.horizontal = 0 }
        glide.vertical = min(max(glide.vertical + vertical * Self.pixelsPerLine, -Self.maxGlide), Self.maxGlide)
        glide.horizontal = min(max(glide.horizontal + horizontal * Self.pixelsPerLine, -Self.maxGlide), Self.maxGlide)
        guard glideTimer == nil else { return }
        lastGlideFrame = Date()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.stepGlide() }
        RunLoop.main.add(timer, forMode: .common)
        glideTimer = timer
    }

    private func stepGlide() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastGlideFrame)
        lastGlideFrame = now
        // Chases the target like Lenis' lerp: each frame covers a share of what's left, so it eases out.
        // smoothness 0…1 → settles in about 200…1000 ms.
        let duration = 0.2 + 0.8 * scroll.smoothness
        let share = 1 - exp(-elapsed / (duration / 4))
        var dy = glide.vertical * share
        var dx = glide.horizontal * share
        if abs(glide.vertical) < 1 { dy = glide.vertical }
        if abs(glide.horizontal) < 1 { dx = glide.horizontal }
        glide.vertical -= dy
        glide.horizontal -= dx

        glide.carryV += dy
        glide.carryH += dx
        let postV = glide.carryV.rounded(.towardZero)
        let postH = glide.carryH.rounded(.towardZero)
        glide.carryV -= postV
        glide.carryH -= postH
        if postV != 0 || postH != 0 { ActionPerformer.postScroll(dx: Int32(postH), dy: Int32(postV)) }
        if glide.vertical == 0 && glide.horizontal == 0 { stopGlide() }
    }

    private func stopGlide() {
        glideTimer?.invalidate()
        glideTimer = nil
        glide = (0, 0, 0, 0)
    }

    // MARK: - Helpers

    private static let axes: [(line: CGEventField, point: CGEventField, fixed: CGEventField)] = [
        (.scrollWheelEventDeltaAxis1, .scrollWheelEventPointDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1),
        (.scrollWheelEventDeltaAxis2, .scrollWheelEventPointDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2),
    ]

    private func scale(_ event: CGEvent, by factor: Double) {
        for axis in Self.axes {
            // Read everything first: setting the line delta makes CoreGraphics recompute the other two.
            let line = Double(event.getIntegerValueField(axis.line)) * factor
            let point = Double(event.getIntegerValueField(axis.point)) * factor
            let fixed = event.getDoubleValueField(axis.fixed) * factor
            event.setIntegerValueField(axis.line, value: Int64(line.rounded(.awayFromZero)))
            event.setIntegerValueField(axis.point, value: Int64(point.rounded()))
            event.setDoubleValueField(axis.fixed, value: fixed)
        }
    }

    private func swapAxes(_ event: CGEvent) {
        let (vertical, horizontal) = (Self.axes[0], Self.axes[1])
        event.setIntegerValueField(horizontal.line, value: event.getIntegerValueField(vertical.line))
        event.setIntegerValueField(horizontal.point, value: event.getIntegerValueField(vertical.point))
        event.setDoubleValueField(horizontal.fixed, value: event.getDoubleValueField(vertical.fixed))
        event.setIntegerValueField(vertical.line, value: 0)
        event.setIntegerValueField(vertical.point, value: 0)
        event.setDoubleValueField(vertical.fixed, value: 0)
    }

    // MARK: Double-click fix

    /// A press while the button's release is still held back: the contact bounced. Drop both, so it stays one press.
    private func guardPress(_ button: Int) -> Bool {
        guard let held = heldUps.removeValue(forKey: button) else { return false }
        held.work.cancel()
        return true
    }

    /// Holds a plain left/right release back for `clickGuard`, then lets it through.
    private func guardRelease(_ button: Int, _ event: CGEvent) -> Bool {
        guard let window = clickGuard, isEnabled, captureHandler == nil, let copy = event.copy() else { return false }
        copy.setIntegerValueField(.eventSourceUserData, value: ActionPerformer.syntheticTag)
        if let state = pressClickState[button] { copy.setIntegerValueField(.mouseEventClickState, value: state) }
        let work = schedule(window) { [weak self] in
            guard self?.heldUps.removeValue(forKey: button) != nil else { return }
            Self.post(copy, button)
        }
        heldUps[button] = (copy, work)
        return true
    }

    /// Lets every held release through now, so no button is left looking pressed.
    private func releaseHeldUps() {
        for (button, held) in heldUps {
            held.work.cancel()
            Self.post(held.event, button)
        }
        heldUps.removeAll()
    }

    private static func post(_ release: CGEvent, _ button: Int) {
        if let recorder = ActionPerformer.recorder { return recorder("release \(button)") }
        release.post(tap: .cghidEventTap)
    }

    // MARK: - Buttons that send key combos

    /// A key pressed or released on a mouse's own keyboard interface, as DeviceMonitor reports it.
    func mouseKey(usage: Int, modifiers: Int, down: Bool) {
        guard let code = MouseKeys.keyCode(usage: usage) else { return }
        guard down else {
            guard let held = keyButtonsDown.removeValue(forKey: code) else { return }
            if held.swallowed { _ = mouseUp(held.button) }
            return
        }
        if mouseKeyCodes.insert(code).inserted { onNewMouseKeyCode?(code) }
        let button = MouseKeys.button(usage: usage, modifiers: modifiers)
        let swallowed = mouseDown(button, [])
        keyButtonsDown[code] = (button, swallowed)
        // The key event may have reached the tap first and be waiting for this report.
        guard let held = heldKeys.removeValue(forKey: code) else { return }
        held.work.cancel()
        if swallowed {
            if held.up == nil { swallowedKeys.insert(code) }
        } else {
            Self.repost(held.down)
            held.up.map(Self.repost)
        }
    }

    /// Returns true when a key event should be swallowed: it is a mouse button that is listened for or mapped.
    private func key(_ down: Bool, _ event: CGEvent) -> Bool {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if !down {
            if swallowedKeys.remove(code) != nil { return true }
            if heldKeys[code] != nil, heldKeys[code]?.up == nil, let copy = event.copy() {
                heldKeys[code]?.up = copy // released before the mouse's report came: decide both together
                return true
            }
            return false
        }
        if swallowedKeys.contains(code) { return true } // auto-repeat of a swallowed press
        if let held = keyButtonsDown[code] {
            if held.swallowed { swallowedKeys.insert(code) }
            return held.swallowed
        }
        // The mouse's report may still be on its way. Wait a moment for keys mice are known to send,
        // or for any key while listening (except Esc, which cancels listening).
        let listening = captureHandler != nil
        guard listening || isEnabled, listening ? code != UInt16(kVK_Escape) : mouseKeyCodes.contains(code),
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0, heldKeys[code] == nil,
              let copy = event.copy() else { return false }
        let work = schedule(Self.mouseKeyWait) { [weak self] in
            guard let held = self?.heldKeys.removeValue(forKey: code) else { return }
            Self.repost(held.down)
            held.up.map(Self.repost)
        }
        heldKeys[code] = (copy, nil, work)
        return true
    }

    /// Lets a held key event through after all, marked so the tap doesn't stop it again.
    private static func repost(_ event: CGEvent) {
        if let recorder = ActionPerformer.recorder {
            return recorder("key passed \(event.getIntegerValueField(.keyboardEventKeycode))")
        }
        event.setIntegerValueField(.eventSourceUserData, value: ActionPerformer.syntheticTag)
        event.post(tap: .cghidEventTap)
    }

    private func deliverCapture(_ trigger: Trigger, _ type: ClickType) {
        guard let handler = captureHandler else { return }
        DispatchQueue.main.async { handler(trigger, type) }
    }

    private func schedule(_ delay: Double, _ block: @escaping () -> Void) -> DispatchWorkItem {
        let work = DispatchWorkItem(block: block)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return work
    }

    /// Runs the click binding, or replays the original click so unmapped click types keep their default behavior.
    private func fire(_ binding: MouseBinding?, _ button: Int) {
        if let binding {
            ActionPerformer.perform(binding)
        } else {
            ActionPerformer.postClick(button: button)
        }
    }

    private func matches(_ binding: MouseBinding, _ trigger: Trigger) -> Bool {
        binding.action != .none && binding.action.isAvailable && binding.trigger == trigger
    }

    private func binding(_ trigger: Trigger, _ clickType: ClickType) -> MouseBinding? {
        bindings.first { matches($0, trigger) && $0.clickType == clickType }
    }
}
