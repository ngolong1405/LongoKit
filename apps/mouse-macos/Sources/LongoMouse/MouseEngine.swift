import AppKit
import ApplicationServices
import LongoKitUI

/// Intercepts extra mouse buttons (middle and up) and the scroll wheel system-wide through a CGEventTap.
/// The tap runs on the main run loop, so all state here is only touched from the main thread.
final class MouseEngine {
    static let shared = MouseEngine()

    var isEnabled = true
    var scroll = ScrollSettings()
    /// macOS "Natural scrolling" (System Settings › Mouse/Trackpad), which the wheel already follows before we see it.
    var systemNaturalScrolling = MouseEngine.readSystemNaturalScrolling()
    private(set) var bindings: [MouseBinding] = []

    /// While set, extra-button gestures are classified and delivered here instead of being remapped.
    var captureHandler: ((Trigger, ClickType) -> Void)?

    private struct Press {
        var trigger: Trigger
        var capturing: Bool
        /// A hold, drag or scroll already fired for this press, so releasing it must not click.
        var used = false
        var dragX = 0.0
        var dragY = 0.0
        var holdTimer: DispatchWorkItem?
    }

    private var tap: CFMachPort?
    private var presses: [Int: Press] = [:]
    private var pendingClicks: [Int: DispatchWorkItem] = [:]
    private var pendingCapture: (button: Int, work: DispatchWorkItem)?
    private var lastSpaceSwitch = Date.distantPast
    /// Smooth scrolling: pixels still to scroll on each axis, and the fractions not yet posted.
    private var glide = (vertical: 0.0, horizontal: 0.0, carryV: 0.0, carryH: 0.0)
    private var glideTimer: Timer?
    private var lastGlideFrame = Date()

    /// Pixels one wheel line scrolls when smooth scrolling animates it (about what browsers use for a line).
    private static let pixelsPerLine = 40.0

    private static let holdDelay = 0.4
    private static let dragThreshold = 40.0
    private static let captureDragThreshold = 12.0

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
        return true
    }

    // MARK: - Event handling

    /// Self-test entry point: runs an event through the tap logic; true when it was swallowed.
    func process(_ type: CGEventType, _ event: CGEvent) -> Bool {
        handle(type, event) == nil
    }

    /// Self-test only: forget any half-finished gesture between cases.
    func resetState() {
        presses.removeAll()
        pendingClicks.values.forEach { $0.cancel() }
        pendingClicks.removeAll()
        pendingCapture?.work.cancel()
        pendingCapture = nil
        stopGlide()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == ActionPerformer.syntheticTag { return pass }
        if type == .scrollWheel { return scrollWheel(event) ? nil : pass }

        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        switch type {
        case .otherMouseDown, .leftMouseDown, .rightMouseDown:
            stopGlide() // a click means the user has arrived
            let modifiers = Modifiers(event.flags)
            // Plain left/right clicks are how you use the Mac (and this app); only modified ones can be remapped.
            if button < 2 && modifiers.isEmpty { return pass }
            return mouseDown(button, modifiers) ? nil : pass
        case .otherMouseUp, .leftMouseUp, .rightMouseUp:
            return mouseUp(button) ? nil : pass
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
        glide.vertical += vertical * Self.pixelsPerLine
        glide.horizontal += horizontal * Self.pixelsPerLine
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
