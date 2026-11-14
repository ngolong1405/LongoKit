import AppKit
import ApplicationServices
import CoreGraphics

/// The displays, in global coordinates (top-left origin, as events have them).
enum Screens {
    static func all() -> [CGRect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    /// Whether `point`, moving by (`dx`, `dy`), pushes out through the outer edge on `side`; if so, how far along
    /// that screen's edge it is (0…1).
    static func leaving(_ point: CGPoint, dx: Double, dy: Double, side: Side, screens: [CGRect] = all()) -> CGFloat? {
        guard let screen = screens.first(where: { $0.insetBy(dx: -1, dy: -1).contains(point) }) else { return nil }
        let union = screens.reduce(CGRect.null) { $0.union($1) }
        switch side {
        case .right:
            guard dx > 0, point.x >= screen.maxX - 1.5, screen.maxX >= union.maxX - 0.5 else { return nil }
            return clamp((point.y - screen.minY) / screen.height)
        case .left:
            guard dx < 0, point.x <= screen.minX + 0.5, screen.minX <= union.minX + 0.5 else { return nil }
            return clamp((point.y - screen.minY) / screen.height)
        case .bottom:
            guard dy > 0, point.y >= screen.maxY - 1.5, screen.maxY >= union.maxY - 0.5 else { return nil }
            return clamp((point.x - screen.minX) / screen.width)
        case .top:
            guard dy < 0, point.y <= screen.minY + 0.5, screen.minY <= union.minY + 0.5 else { return nil }
            return clamp((point.x - screen.minX) / screen.width)
        }
    }

    /// Where the pointer comes in on `side` of these screens, `fraction` along the edge, a point inside.
    static func entry(_ side: Side, _ fraction: CGFloat, screens: [CGRect] = all()) -> CGPoint {
        let union = screens.reduce(CGRect.null) { $0.union($1) }
        let edge: [CGRect]
        switch side {
        case .left: edge = screens.filter { $0.minX <= union.minX + 0.5 }
        case .right: edge = screens.filter { $0.maxX >= union.maxX - 0.5 }
        case .top: edge = screens.filter { $0.minY <= union.minY + 0.5 }
        case .bottom: edge = screens.filter { $0.maxY >= union.maxY - 0.5 }
        }
        // The biggest of the screens on that edge.
        let screen = edge.max { $0.width * $0.height < $1.width * $1.height } ?? union
        switch side {
        case .left: return CGPoint(x: screen.minX + 2, y: screen.minY + fraction * (screen.height - 1))
        case .right: return CGPoint(x: screen.maxX - 3, y: screen.minY + fraction * (screen.height - 1))
        case .top: return CGPoint(x: screen.minX + fraction * (screen.width - 1), y: screen.minY + 2)
        case .bottom: return CGPoint(x: screen.minX + fraction * (screen.width - 1), y: screen.maxY - 3)
        }
    }

    /// `point` kept on a screen: the nearest point of the nearest one.
    static func clamp(_ point: CGPoint, screens: [CGRect] = all()) -> CGPoint {
        if screens.contains(where: { $0.contains(point) }) { return point }
        var best = point
        var distance = CGFloat.infinity
        for screen in screens {
            let inside = CGPoint(x: min(max(point.x, screen.minX), screen.maxX - 1), y: min(max(point.y, screen.minY), screen.maxY - 1))
            let d = hypot(inside.x - point.x, inside.y - point.y)
            if d < distance {
                distance = d
                best = inside
            }
        }
        return best
    }

    private static func clamp(_ value: CGFloat) -> CGFloat { min(max(value, 0), 1) }
}

/// The keyboard and mouse going over to another Mac and back.
///
/// Controlling: an event tap sees the pointer push past the edge where a connected Mac sits; from then on the
/// pointer here is parked and hidden, every mouse and keyboard event is held back from this Mac and sent instead,
/// until the other Mac says the pointer came back. Controlled: the other Mac's events are posted here, as from a
/// mouse and keyboard plugged in, the pointer tracked here; pushed back out the way it came, it goes home.
final class InputBridge: @unchecked Sendable {
    /// Posted events carry this, so this Mac's own tap lets them by.
    private static let marker: Int64 = 0x4C_4F_4E_47_46_4C_4F_57

    private enum State {
        case idle
        case controlling(mac: String, side: Side)
        case controlled(by: String, side: Side)
    }

    private let lock = NSLock()
    private var state = State.idle
    /// Where each connected Mac sits.
    private var sides: [String: Side] = [:]
    private var tap: CFMachPort?
    private var thread: Thread?
    private var escapes: [Date] = []
    /// Controlled: the pointer, buttons held, the last click (for double clicks).
    private var pointer = CGPoint.zero
    private var held: Set<Int> = []
    private var lastClick: (button: Int, at: Date, point: CGPoint, count: Int64)?
    private var modifiers: CGEventFlags = []
    private let source = CGEventSource(stateID: .hidSystemState)

    /// Sends a message to a Mac.
    var send: (Message, String) -> Void = { _, _ in }
    /// Control went over to `mac` (nil: it came back here).
    var controlling: (String?) -> Void = { _ in }
    /// Another Mac took over here (nil: it let go).
    var controlledBy: (String?) -> Void = { _ in }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func askForAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func setSides(_ sides: [String: Side]) {
        lock.lock()
        self.sides = sides
        let current = state
        lock.unlock()
        // The Mac in control left the network: take the keyboard and mouse back.
        if case .controlling(let mac, _) = current, sides[mac] == nil { comeBack(fraction: nil) }
        if case .controlled(let mac, _) = current, sides[mac] == nil { letGo() }
    }

    // MARK: - The tap

    /// Starts watching the mouse and keyboard (needs Accessibility); false when it can't.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        Cursor.allowHidingInBackground()
        // Moving the pointer in code holds the real mouse back for a quarter second by default: not here, or every
        // crossing would stall.
        source?.localEventsSuppressionInterval = 0
        CGEventSource(stateID: .combinedSessionState)?.localEventsSuppressionInterval = 0
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                    .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
                                    .scrollWheel, .keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, info in
                                              let bridge = Unmanaged<InputBridge>.fromOpaque(info!).takeUnretainedValue()
                                              return bridge.handle(type, event)
                                          }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        // Its own thread, so a busy main thread never holds the mouse up.
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "LongoFlow.tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
        return true
    }

    func stop() {
        comeBack(fraction: nil)
        letGo()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        thread = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker { return Unmanaged.passUnretained(event) }
        lock.lock()
        let current = state
        let sides = self.sides
        lock.unlock()
        switch current {
        case .idle:
            if type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged {
                let dx = event.getDoubleValueField(.mouseEventDeltaX), dy = event.getDoubleValueField(.mouseEventDeltaY)
                for (mac, side) in sides {
                    if let fraction = Screens.leaving(event.location, dx: dx, dy: dy, side: side) {
                        goOver(to: mac, side: side, fraction: fraction, at: event.location)
                        return nil
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        case .controlling(let mac, _):
            forward(type, event, to: mac)
            return nil
        case .controlled:
            // This Mac's own mouse and keyboard still work meanwhile.
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Controlling

    private func goOver(to mac: String, side: Side, fraction: CGFloat, at point: CGPoint) {
        lock.lock()
        state = .controlling(mac: mac, side: side)
        escapes = []
        lock.unlock()
        var writer = Writer()
        writer.u8(side.opposite.rawValue)
        writer.f32(Float(fraction))
        send(Message(.enter, writer.data), mac)
        // Parked a little inside the edge, hidden, while the other Mac has it.
        Cursor.park(at: Screens.clamp(Screens.entry(side, fraction)))
        controlling(mac)
    }

    private func forward(_ type: CGEventType, _ event: CGEvent, to mac: String) {
        var writer = Writer()
        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            writer.f32(Float(event.getDoubleValueField(.mouseEventDeltaX)))
            writer.f32(Float(event.getDoubleValueField(.mouseEventDeltaY)))
            send(Message(.move, writer.data), mac)
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            writer.u8(UInt8(clamping: event.getIntegerValueField(.mouseEventButtonNumber)))
            writer.u8(type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown ? 1 : 0)
            send(Message(.button, writer.data), mac)
        case .scrollWheel:
            let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            writer.u8(continuous ? 1 : 0)
            if continuous {
                writer.f32(Float(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)))
                writer.f32(Float(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)))
            } else {
                writer.f32(Float(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)))
                writer.f32(Float(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)))
            }
            writer.u8(UInt8(clamping: event.getIntegerValueField(.scrollWheelEventScrollPhase)))
            writer.u8(UInt8(clamping: event.getIntegerValueField(.scrollWheelEventMomentumPhase)))
            send(Message(.scroll, writer.data), mac)
        case .keyDown, .keyUp:
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            // Esc three times within a second: the keyboard and mouse come back, whatever the other Mac does.
            if type == .keyDown && code == 53 && event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                let now = Date()
                lock.lock()
                escapes = escapes.filter { now.timeIntervalSince($0) < 1 } + [now]
                let three = escapes.count >= 3
                lock.unlock()
                if three {
                    send(Message(.release), mac)
                    comeBack(fraction: nil)
                    return
                }
            }
            writer.u16(code)
            writer.u8(type == .keyDown ? 1 : 0)
            writer.u64(event.flags.rawValue)
            writer.u8(event.getIntegerValueField(.keyboardEventAutorepeat) != 0 ? 1 : 0)
            send(Message(.key, writer.data), mac)
        case .flagsChanged:
            writer.u16(UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
            writer.u64(event.flags.rawValue)
            send(Message(.flags, writer.data), mac)
        default:
            break
        }
    }

    /// The pointer is back here (the other Mac sent it back at `fraction` along the edge, or it's taken back).
    func comeBack(fraction: CGFloat?) {
        lock.lock()
        guard case .controlling(_, let side) = state else {
            lock.unlock()
            return
        }
        state = .idle
        lock.unlock()
        let point = fraction.map { Screens.entry(side, $0) }
        Cursor.release(at: point)
        controlling(nil)
    }

    // MARK: - Controlled

    /// A message from a connected Mac.
    func received(_ message: Message, from mac: String) {
        var reader = Reader(message.payload)
        switch message.kind {
        case .enter:
            guard let raw = reader.u8(), let side = Side(rawValue: raw), let fraction = reader.f32() else { return }
            lock.lock()
            state = .controlled(by: mac, side: side)
            pointer = Screens.entry(side, CGFloat(fraction))
            held = []
            modifiers = []
            lock.unlock()
            CGWarpMouseCursorPosition(pointer)
            post(mouse: .mouseMoved, button: .left)
            controlledBy(mac)
        case .leave:
            guard let fraction = reader.f32() else { return }
            comeBack(fraction: CGFloat(fraction))
        case .release:
            letGo()
        case .move:
            guard let dx = reader.f32(), let dy = reader.f32() else { return }
            move(dx: CGFloat(dx), dy: CGFloat(dy), from: mac)
        case .button:
            guard let number = reader.u8(), let down = reader.u8() else { return }
            press(Int(number), down: down == 1)
        case .scroll:
            guard let continuous = reader.u8(), let dy = reader.f32(), let dx = reader.f32() else { return }
            let phase = reader.u8() ?? 0, momentum = reader.u8() ?? 0
            guard isControlled(by: mac),
                  let event = CGEvent(scrollWheelEvent2Source: source, units: continuous == 1 ? .pixel : .line,
                                      wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else { return }
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: Int64(continuous))
            if continuous == 1 {
                event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(dy))
                event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(dx))
            }
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase))
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum))
            event.location = pointer
            post(event)
        case .key:
            guard let code = reader.u16(), let down = reader.u8(), let flags = reader.u64(), isControlled(by: mac),
                  let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down == 1) else { return }
            event.flags = CGEventFlags(rawValue: flags)
            event.setIntegerValueField(.keyboardEventAutorepeat, value: Int64(reader.u8() ?? 0))
            post(event)
        case .flags:
            guard let code = reader.u16(), let flags = reader.u64(), isControlled(by: mac),
                  let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) else { return }
            event.type = .flagsChanged
            event.flags = CGEventFlags(rawValue: flags)
            lock.lock()
            modifiers = event.flags
            lock.unlock()
            post(event)
        default:
            break
        }
    }

    private func isControlled(by mac: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .controlled(let by, _) = state { return by == mac }
        return false
    }

    private func move(dx: CGFloat, dy: CGFloat, from mac: String) {
        lock.lock()
        guard case .controlled(let by, let side) = state, by == mac else {
            lock.unlock()
            return
        }
        let screens = Screens.all()
        let target = CGPoint(x: pointer.x + dx, y: pointer.y + dy)
        // Pushed back out the edge it came in by: it goes home.
        if let fraction = Screens.leaving(pointer, dx: Double(dx), dy: Double(dy), side: side, screens: screens),
           !screens.contains(where: { $0.contains(target) }) {
            lock.unlock()
            var writer = Writer()
            writer.f32(Float(fraction))
            letGo()
            send(Message(.leave, writer.data), mac)
            return
        }
        pointer = Screens.clamp(target, screens: screens)
        let dragging = held.min()
        lock.unlock()
        switch dragging {
        case 0?: post(mouse: .leftMouseDragged, button: .left, dx: dx, dy: dy)
        case 1?: post(mouse: .rightMouseDragged, button: .right, dx: dx, dy: dy)
        case let other?: post(mouse: .otherMouseDragged, button: CGMouseButton(rawValue: UInt32(other)) ?? .center, dx: dx, dy: dy)
        case nil: post(mouse: .mouseMoved, button: .left, dx: dx, dy: dy)
        }
    }

    private func press(_ number: Int, down: Bool) {
        lock.lock()
        guard case .controlled = state else {
            lock.unlock()
            return
        }
        if down { held.insert(number) } else { held.remove(number) }
        // Clicks close in time and place count up: double and triple clicks.
        var count: Int64 = 1
        if down {
            if let last = lastClick, last.button == number, Date().timeIntervalSince(last.at) < NSEvent.doubleClickInterval,
               hypot(last.point.x - pointer.x, last.point.y - pointer.y) < 5 {
                count = last.count + 1
            }
            lastClick = (number, Date(), pointer, count)
        } else {
            count = lastClick?.count ?? 1
        }
        lock.unlock()
        let type: CGEventType
        switch (number, down) {
        case (0, true): type = .leftMouseDown
        case (0, false): type = .leftMouseUp
        case (1, true): type = .rightMouseDown
        case (1, false): type = .rightMouseUp
        case (_, true): type = .otherMouseDown
        case (_, false): type = .otherMouseUp
        }
        post(mouse: type, button: CGMouseButton(rawValue: UInt32(number)) ?? .left, clicks: count)
    }

    /// The other Mac let go: anything it held (buttons, modifiers) is let up, so nothing stays stuck.
    func letGo() {
        lock.lock()
        guard case .controlled = state else {
            lock.unlock()
            return
        }
        let buttons = held
        let hadModifiers = !modifiers.isEmpty
        state = .idle
        held = []
        modifiers = []
        lock.unlock()
        for button in buttons {
            let type: CGEventType = button == 0 ? .leftMouseUp : button == 1 ? .rightMouseUp : .otherMouseUp
            post(mouse: type, button: CGMouseButton(rawValue: UInt32(button)) ?? .left, force: true)
        }
        if hadModifiers, let event = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false) {
            event.type = .flagsChanged
            event.flags = []
            post(event)
        }
        controlledBy(nil)
    }

    private func post(mouse type: CGEventType, button: CGMouseButton, dx: CGFloat = 0, dy: CGFloat = 0, clicks: Int64 = 1, force: Bool = false) {
        lock.lock()
        let point = pointer
        let flags = modifiers
        lock.unlock()
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: clicks)
        event.setDoubleValueField(.mouseEventDeltaX, value: Double(dx))
        event.setDoubleValueField(.mouseEventDeltaY, value: Double(dy))
        event.flags = flags
        post(event)
    }

    private func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: .cghidEventTap)
    }
}

/// The pointer while another Mac has the mouse: parked where it left and hidden, then shown again.
enum Cursor {
    private static var hidden = false

    /// A background app can't hide the pointer unless the window server is told it may (what Barrier and other
    /// mouse-sharing apps do).
    static func allowHidingInBackground() {
        typealias Connection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        guard let handle = dlopen(nil, RTLD_NOW),
              let main = dlsym(handle, "_CGSDefaultConnection"),
              let set = dlsym(handle, "CGSSetConnectionProperty") else { return }
        let connection = unsafeBitCast(main, to: Connection.self)()
        _ = unsafeBitCast(set, to: SetProperty.self)(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }

    static func park(at point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(0)
        DispatchQueue.main.async {
            guard !hidden else { return }
            CGDisplayHideCursor(CGMainDisplayID())
            hidden = true
        }
    }

    static func release(at point: CGPoint?) {
        if let point { CGWarpMouseCursorPosition(point) }
        CGAssociateMouseAndMouseCursorPosition(1)
        DispatchQueue.main.async {
            guard hidden else { return }
            CGDisplayShowCursor(CGMainDisplayID())
            hidden = false
        }
    }
}
