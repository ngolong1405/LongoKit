import AppKit
import ApplicationServices
import CoreGraphics
import ImageIO

/// The displays, in global coordinates (top-left origin, as events have them).
enum Screens {
    static func all() -> [CGRect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    /// The pointer at `point` moving by (`dx`, `dy`): when that leaves these screens and lands on one of `other`'s
    /// (placed at `offset` here), where on it, in its own coordinates.
    static func crossing(_ point: CGPoint, dx: Double, dy: Double, local: [CGRect], into other: [CGRect], at offset: CGPoint) -> CGPoint? {
        guard dx != 0 || dy != 0 else { return nil }
        // At least two points on: a slow push at the edge still gets over it.
        let step = max(abs(dx), abs(dy))
        let scale = step < 2 ? 2 / step : 1
        let target = CGPoint(x: point.x + dx * scale, y: point.y + dy * scale)
        guard !local.contains(where: { $0.contains(target) }) else { return nil }
        for screen in other {
            let placed = screen.offsetBy(dx: offset.x, dy: offset.y)
            guard placed.insetBy(dx: -3, dy: -3).contains(target) else { continue }
            let there = CGPoint(x: target.x - offset.x, y: target.y - offset.y)
            return CGPoint(x: min(max(there.x, screen.minX + 1), screen.maxX - 2), y: min(max(there.y, screen.minY + 1), screen.maxY - 2))
        }
        // Not touching: straight on the way it was pushed, across a gap, to the nearest of the other's displays that
        // lines up with the pointer, unless one of this Mac's displays is in the way.
        let horizontal = abs(dx) >= abs(dy)
        var best: (screen: CGRect, gap: CGFloat)?
        for screen in other {
            let placed = screen.offsetBy(dx: offset.x, dy: offset.y)
            let gap: CGFloat
            let between: CGRect
            if horizontal {
                guard point.y >= placed.minY, point.y < placed.maxY else { continue }
                gap = dx > 0 ? placed.minX - point.x : point.x - placed.maxX
                between = CGRect(x: dx > 0 ? point.x + 1 : placed.maxX, y: point.y, width: max(gap - 1, 0), height: 1)
            } else {
                guard point.x >= placed.minX, point.x < placed.maxX else { continue }
                gap = dy > 0 ? placed.minY - point.y : point.y - placed.maxY
                between = CGRect(x: point.x, y: dy > 0 ? point.y + 1 : placed.maxY, width: 1, height: max(gap - 1, 0))
            }
            guard gap >= -1, gap <= maxGap, !local.contains(where: { $0.intersects(between) }) else { continue }
            if best == nil || gap < best!.gap { best = (screen, gap) }
        }
        guard let screen = best?.screen else { return nil }
        let placed = screen.offsetBy(dx: offset.x, dy: offset.y)
        let entry = horizontal
            ? CGPoint(x: dx > 0 ? placed.minX + 1 : placed.maxX - 2, y: point.y)
            : CGPoint(x: point.x, y: dy > 0 ? placed.minY + 1 : placed.maxY - 2)
        return CGPoint(x: entry.x - offset.x, y: entry.y - offset.y)
    }

    /// How far across empty desk the pointer jumps to another Mac's display (in points).
    static let maxGap: CGFloat = 2400

    /// Displays dropped at `offset` here (another Mac's, or one of this Mac's), moved to the nearest place where they
    /// touch one of `local` edge to edge, sharing a stretch of it, covering none of `local` or `avoiding`: as macOS
    /// arranges displays. Close to lining up with the display they touch (top with top, bottom with bottom, side with
    /// side), they line up, so the desk stays tidy.
    static func snap(_ other: [CGRect], at offset: CGPoint, to local: [CGRect], avoiding: [CGRect] = []) -> CGPoint {
        let group = other.reduce(CGRect.null) { $0.union($1) }.offsetBy(dx: offset.x, dy: offset.y)
        guard !group.isNull, !local.isEmpty else { return offset }
        let pull: CGFloat = 50
        func lined(_ value: CGFloat, _ length: CGFloat, _ start: CGFloat, _ end: CGFloat) -> CGFloat {
            if abs(value - start) < pull { return start }
            if abs(value + length - end) < pull { return end - length }
            return value
        }
        var best: (move: CGPoint, distance: CGFloat)?
        for screen in local {
            let shareY = min(80, group.height / 3, screen.height / 3), shareX = min(80, group.width / 3, screen.width / 3)
            let y = lined(min(max(group.minY, screen.minY - group.height + shareY), screen.maxY - shareY), group.height, screen.minY, screen.maxY)
            let x = lined(min(max(group.minX, screen.minX - group.width + shareX), screen.maxX - shareX), group.width, screen.minX, screen.maxX)
            let spots = [CGPoint(x: screen.maxX, y: y), CGPoint(x: screen.minX - group.width, y: y),
                         CGPoint(x: x, y: screen.maxY), CGPoint(x: x, y: screen.minY - group.height)]
            for spot in spots {
                let placed = CGRect(origin: spot, size: group.size)
                // Edge to edge is fine; covering a display isn't.
                if (local + avoiding).contains(where: { $0.insetBy(dx: 1, dy: 1).intersects(placed) }) { continue }
                let move = CGPoint(x: spot.x - group.minX, y: spot.y - group.minY)
                let distance = hypot(move.x, move.y)
                if best == nil || distance < best!.distance { best = (move, distance) }
            }
        }
        guard let move = best?.move else { return offset }
        return CGPoint(x: offset.x + move.x, y: offset.y + move.y)
    }

    /// The displays with their ids, in the order `all()` gives them.
    static func displays() -> [(id: CGDirectDisplayID, frame: CGRect)] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).map { ($0, CGDisplayBounds($0)) }
    }

    /// Moves this Mac's displays, as dragging them in System Settings › Displays does. The main display stays at
    /// (0, 0), so moving it moves the others instead; returns how far everything shifted for that (to move the
    /// other Macs' places by as much).
    @discardableResult
    static func arrange(_ frames: [CGRect]) -> CGPoint {
        let ids = displays()
        guard ids.count == frames.count, let main = ids.firstIndex(where: { CGDisplayIsMain($0.id) != 0 }) else { return .zero }
        let shift = frames[main].origin
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return .zero }
        for (index, display) in ids.enumerated() {
            let origin = CGPoint(x: frames[index].minX - shift.x, y: frames[index].minY - shift.y)
            CGConfigureDisplayOrigin(config, display.id, Int32(origin.x.rounded()), Int32(origin.y.rounded()))
        }
        guard CGCompleteDisplayConfiguration(config, .permanently) == .success else {
            CGCancelDisplayConfiguration(config)
            return .zero
        }
        return CGPoint(x: -shift.x, y: -shift.y)
    }

    /// Each display's wallpaper, small (a JPEG about 360 points wide), in `all()`'s order; nil where there's none to read.
    @MainActor static func wallpapers() -> [Data?] {
        guard let main = NSScreen.screens.first else { return [] }
        return all().map { rect in
            guard let screen = NSScreen.screens.first(where: {
                abs($0.frame.minX - rect.minX) < 1 && abs((main.frame.maxY - $0.frame.maxY) - rect.minY) < 1
            }), let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
            return thumbnail(url)
        }
    }

    private static var thumbnails: [URL: Data] = [:]

    private static func thumbnail(_ url: URL) -> Data? {
        if let cached = thumbnails[url] { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                         kCGImageSourceThumbnailMaxPixelSize: 720,
                                                                         kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        else { return nil }
        let data = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.72])
        thumbnails[url] = data
        return data
    }

    /// Which of these displays is the laptop's own (nil on a desktop Mac, or with the lid closed).
    static func builtin(in screens: [CGRect]) -> Int? {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        guard let id = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) else { return nil }
        let bounds = CGDisplayBounds(id)
        return screens.firstIndex { abs($0.minX - bounds.minX) < 1 && abs($0.minY - bounds.minY) < 1 }
    }

    /// This Mac's displays by name ("Built-in Retina Display", "DELL U2723QE"), keyed by their place.
    @MainActor static func names() -> [String: String] {
        guard let main = NSScreen.screens.first else { return [:] }
        var names: [String: String] = [:]
        for screen in NSScreen.screens {
            // AppKit's frames have the origin bottom-left of the main display; events', top-left.
            let frame = screen.frame
            names[key(CGRect(x: frame.minX, y: main.frame.maxY - frame.maxY, width: frame.width, height: frame.height))] = screen.localizedName
        }
        return names
    }

    /// A display's name, short: "Built-in" for a laptop's own, a monitor's as it calls itself (cut to fit).
    static func short(_ name: String) -> String {
        if name.localizedCaseInsensitiveContains("built-in") || name.localizedCaseInsensitiveContains("tích hợp") { return "Built-in" }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 18 ? String(trimmed.prefix(17)) + "…" : trimmed
    }

    /// A display's place as a key (CGRect is only hashable from macOS 15).
    static func key(_ rect: CGRect) -> String {
        "\(Int(rect.minX.rounded())),\(Int(rect.minY.rounded())),\(Int(rect.width.rounded())),\(Int(rect.height.rounded()))"
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
    /// macOS's system-defined event type (NX_SYSDEFINED), which carries the media keys as subtype 8.
    private static let systemDefined: UInt32 = 14
    private static let mediaKeys: Int16 = 8

    /// Posted events carry this, so this Mac's own tap lets them by.
    private static let marker: Int64 = 0x4C_4F_4E_47_46_4C_4F_57

    private enum State {
        case idle
        case controlling(mac: String)
        case controlled(by: String)
    }

    /// A connected Mac: its displays, and where they sit here.
    struct Peer {
        var screens: [CGRect]
        var offset: CGPoint
    }

    private let lock = NSLock()
    private var state = State.idle
    /// The connected Macs that are placed.
    private var peers: [String: Peer] = [:]
    /// This Mac's displays (kept, not asked for at every pointer move).
    private var screens = Screens.all()
    private var tap: CFMachPort?
    private var thread: Thread?
    private var escapes: [Date] = []
    /// Controlled: the pointer, buttons held, the last click (for double clicks).
    private var pointer = CGPoint.zero
    private var held: Set<Int> = []
    private var lastClick: (button: Int, at: Date, point: CGPoint, count: Int64)?
    private var modifiers: CGEventFlags = []
    private let source = CGEventSource(stateID: .hidSystemState)
    /// Controlling: pointer moves gathered for a few milliseconds (a 1000 Hz mouse would send a thousand messages a
    /// second), and a keep-awake while the pointer is over.
    private let timing = DispatchQueue(label: "LongoFlow.timing", qos: .userInteractive)
    private var pending = CGPoint.zero
    private var lastMove: UInt64 = 0
    private var flushArmed = false
    private var awake: DispatchSourceTimer?
    private static let gather: UInt64 = 4_000_000

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

    func setPeers(_ peers: [String: Peer]) {
        lock.lock()
        self.peers = peers
        let current = state
        lock.unlock()
        // The Mac in control left the network: take the keyboard and mouse back.
        if case .controlling(let mac) = current, peers[mac] == nil { comeBack(at: nil) }
        if case .controlled(let mac) = current, peers[mac] == nil { letGo() }
    }

    /// This Mac's displays changed (one plugged in, moved, or gone).
    func screensChanged() {
        let now = Screens.all()
        lock.lock()
        screens = now
        lock.unlock()
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
        // And macOS's system-defined events (14): the media keys.
        let mask = types.reduce(CGEventMask(1 << Self.systemDefined)) { $0 | (1 << $1.rawValue) }
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
        comeBack(at: nil)
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
        let peers = self.peers
        let local = screens
        lock.unlock()
        switch current {
        case .idle:
            if type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged {
                let dx = event.getDoubleValueField(.mouseEventDeltaX), dy = event.getDoubleValueField(.mouseEventDeltaY)
                for (mac, peer) in peers {
                    if let there = Screens.crossing(event.location, dx: dx, dy: dy, local: local, into: peer.screens, at: peer.offset) {
                        goOver(to: mac, at: there, leaving: event.location)
                        return nil
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        case .controlling(let mac):
            if type.rawValue == Self.systemDefined {
                // Only the media keys go over; anything else system-defined stays here.
                guard let system = NSEvent(cgEvent: event), system.subtype.rawValue == Self.mediaKeys else { return Unmanaged.passUnretained(event) }
                flush(to: mac)
                var writer = Writer()
                writer.u16(UInt16(bitPattern: system.subtype.rawValue))
                writer.u64(UInt64(bitPattern: Int64(system.data1)))
                writer.u64(UInt64(system.modifierFlags.rawValue))
                send(Message(.system, writer.data), mac)
                return nil
            }
            forward(type, event, to: mac)
            return nil
        case .controlled:
            // This Mac's own mouse and keyboard still work meanwhile.
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Controlling

    private func goOver(to mac: String, at there: CGPoint, leaving here: CGPoint) {
        lock.lock()
        state = .controlling(mac: mac)
        escapes = []
        let local = screens
        lock.unlock()
        var writer = Writer()
        writer.point(there)
        send(Message(.enter, writer.data), mac)
        keepAwake(mac)
        // Parked where it left, hidden, while the other Mac has it.
        Cursor.park(at: Screens.clamp(here, screens: local))
        controlling(mac)
    }

    private func forward(_ type: CGEventType, _ event: CGEvent, to mac: String) {
        var writer = Writer()
        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            gather(dx: event.getDoubleValueField(.mouseEventDeltaX), dy: event.getDoubleValueField(.mouseEventDeltaY), to: mac)
            return
        default:
            // Moves gathered so far go first, so a click lands where the pointer is.
            flush(to: mac)
        }
        switch type {
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
                    comeBack(at: nil)
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

    private func gather(dx: Double, dy: Double, to mac: String) {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        pending.x += dx
        pending.y += dy
        let due = now - lastMove >= Self.gather
        let arm = !due && !flushArmed
        if arm { flushArmed = true }
        lock.unlock()
        if due {
            flush(to: mac)
        } else if arm {
            timing.asyncAfter(deadline: .now() + .nanoseconds(Int(Self.gather))) { [weak self] in self?.flush(to: mac) }
        }
    }

    private func flush(to mac: String) {
        lock.lock()
        let move = pending
        pending = .zero
        flushArmed = false
        lastMove = DispatchTime.now().uptimeNanoseconds
        let over: Bool
        if case .controlling(let current) = state { over = current == mac } else { over = false }
        lock.unlock()
        guard over, move != .zero else { return }
        var writer = Writer()
        writer.f32(Float(move.x))
        writer.f32(Float(move.y))
        send(Message(.move, writer.data), mac)
    }

    /// While the pointer is over (either way): a tiny message every 30 ms, so neither Mac's Wi-Fi dozes off between
    /// moves and holds them back.
    private func keepAwake(_ mac: String?) {
        // On its own queue: it's started and stopped from the tap's thread and the links'.
        timing.async { [self] in
            awake?.cancel()
            awake = nil
            guard let mac else { return }
            let timer = DispatchSource.makeTimerSource(queue: timing)
            timer.schedule(deadline: .now() + .milliseconds(30), repeating: .milliseconds(30), leeway: .milliseconds(5))
            timer.setEventHandler { [weak self] in self?.send(Message(.awake), mac) }
            timer.resume()
            awake = timer
        }
    }

    /// The pointer is back here (the other Mac sent it back to `point`, or it's taken back where it left).
    func comeBack(at point: CGPoint?) {
        lock.lock()
        guard case .controlling = state else {
            lock.unlock()
            return
        }
        state = .idle
        pending = .zero
        let local = screens
        lock.unlock()
        keepAwake(nil)
        Cursor.release(at: point.map { Screens.clamp($0, screens: local) })
        controlling(nil)
    }

    // MARK: - Controlled

    /// A message from a connected Mac.
    func received(_ message: Message, from mac: String) {
        var reader = Reader(message.payload)
        switch message.kind {
        case .enter:
            guard let point = reader.point() else { return }
            lock.lock()
            state = .controlled(by: mac)
            pointer = Screens.clamp(point, screens: screens)
            held = []
            modifiers = []
            lock.unlock()
            CGWarpMouseCursorPosition(pointer)
            post(mouse: .mouseMoved, button: .left)
            keepAwake(mac)
            controlledBy(mac)
        case .leave:
            guard let point = reader.point() else { return }
            comeBack(at: point)
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
        case .system:
            guard let subtype = reader.u16(), let data = reader.u64(), let flags = reader.u64(), isControlled(by: mac) else { return }
            // Made through AppKit, the only way to make one of these; posted from the main thread, as AppKit wants.
            DispatchQueue.main.async { [self] in
                guard let system = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                                      modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                                                      subtype: Int16(bitPattern: subtype), data1: Int(Int64(bitPattern: data)), data2: -1),
                      let event = system.cgEvent else { return }
                post(event)
            }
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
        if case .controlled(let by) = state { return by == mac }
        return false
    }

    private func move(dx: CGFloat, dy: CGFloat, from mac: String) {
        lock.lock()
        guard case .controlled(let by) = state, by == mac else {
            lock.unlock()
            return
        }
        let screens = self.screens
        let target = CGPoint(x: pointer.x + dx, y: pointer.y + dy)
        // Pushed over onto the controlling Mac's screens, where they sit here: it goes home, to that point there.
        if let home = peers[mac],
           let there = Screens.crossing(pointer, dx: Double(dx), dy: Double(dy), local: screens, into: home.screens, at: home.offset) {
            lock.unlock()
            var writer = Writer()
            writer.point(there)
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
        keepAwake(nil)
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
