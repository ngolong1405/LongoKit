import AppKit
import LongoKitUI

/// What the user picked on the overlay.
enum Selection {
    /// `rect` is in points from the display's top-left; `.null` for the whole display.
    case area(display: CGDirectDisplayID, rect: CGRect, scale: CGFloat)
    case window(CGWindowID)
}

/// The dimmed layer drawn over every screen while picking an area or a window. It exists only while picking:
/// one panel per screen, made when a shortcut is pressed and gone as soon as the pick is made or cancelled.
@MainActor
final class SelectionOverlay {
    enum Mode { case area, window }

    private static var current: SelectionOverlay?

    private var panels: [OverlayPanel] = []
    private var mode: Mode
    private let hint: String
    private let allowsWindows: Bool
    private let completion: (Selection?) -> Void
    /// On-screen windows of other apps, front to back, in global top-left coordinates.
    private let windows: [(id: CGWindowID, frame: CGRect)]

    /// Starts picking; `completion` gets nil when it's cancelled. Picking again while picking does nothing.
    static func pick(_ mode: Mode, hint: String, allowsWindows: Bool = true, completion: @escaping (Selection?) -> Void) {
        guard current == nil else { return }
        let overlay = SelectionOverlay(mode: mode, hint: hint, allowsWindows: allowsWindows, completion: completion)
        current = overlay
        overlay.show()
    }

    private init(mode: Mode, hint: String, allowsWindows: Bool, completion: @escaping (Selection?) -> Void) {
        self.mode = mode
        self.hint = hint
        self.allowsWindows = allowsWindows
        self.completion = completion
        windows = Self.visibleWindows()
    }

    private func show() {
        let pointer = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let panel = OverlayPanel(screen: screen)
            let view = OverlayView(overlay: self, screen: screen)
            panel.contentView = view
            panel.orderFrontRegardless()
            panels.append(panel)
            if NSMouseInRect(pointer, screen.frame, false) {
                panel.makeKey()
                panel.makeFirstResponder(view)
            }
        }
        NSCursor.crosshair.push()
        refresh()
    }

    fileprivate var currentMode: Mode { mode }
    fileprivate var hintText: String { hint }

    fileprivate func toggleMode() {
        guard allowsWindows else { return }
        mode = mode == .area ? .window : .area
        refresh()
    }

    fileprivate func refresh() {
        for panel in panels { panel.contentView?.needsDisplay = true }
    }

    /// The frontmost window under a point (global top-left coordinates).
    fileprivate func window(at point: CGPoint) -> (id: CGWindowID, frame: CGRect)? {
        windows.first { $0.frame.contains(point) }
    }

    fileprivate func finish(_ selection: Selection?) {
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        NSCursor.pop()
        Self.current = nil
        completion(selection)
    }

    private static func visibleWindows() -> [(id: CGWindowID, frame: CGRect)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let me = getpid()
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != me,
                  ((info[kCGWindowAlpha as String] as? Double) ?? 1) > 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width > 40, frame.height > 40 else { return nil }
            return (id, frame)
        }
    }
}

private final class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
}

private final class OverlayView: NSView {
    private unowned let overlay: SelectionOverlay
    private let screen: NSScreen
    /// Where this screen sits in global top-left coordinates (the ones window frames use).
    private let origin: CGPoint
    private var dragStart: CGPoint?
    private var dragRect: CGRect?
    private var pointer: CGPoint?

    init(overlay: SelectionOverlay, screen: NSScreen) {
        self.overlay = overlay
        self.screen = screen
        origin = CGDisplayBounds(screen.displayID).origin
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func local(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    /// The highlighted window, in this view's coordinates.
    private var hoveredWindow: (id: CGWindowID, rect: CGRect)? {
        guard overlay.currentMode == .window, let pointer else { return nil }
        let global = CGPoint(x: pointer.x + origin.x, y: pointer.y + origin.y)
        guard let window = overlay.window(at: global) else { return nil }
        return (window.id, window.frame.offsetBy(dx: -origin.x, dy: -origin.y))
    }

    override func mouseMoved(with event: NSEvent) {
        pointer = local(event)
        if !(window?.isKeyWindow ?? false) { window?.makeKey(); window?.makeFirstResponder(self) }
        overlay.refresh()
    }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = local(event)
        if overlay.currentMode == .window {
            pointer = point
            if let hovered = hoveredWindow { overlay.finish(.window(hovered.id)) }
            return
        }
        dragStart = point
        dragRect = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        var point = local(event)
        point.x = min(max(point.x, 0), bounds.width)
        point.y = min(max(point.y, 0), bounds.height)
        pointer = point
        dragRect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                          width: abs(point.x - start.x), height: abs(point.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        guard let rect = dragRect?.integral, rect.width >= 4, rect.height >= 4 else {
            dragRect = nil
            needsDisplay = true
            return
        }
        overlay.finish(.area(display: screen.displayID, rect: rect, scale: screen.backingScaleFactor))
    }

    override func rightMouseDown(with event: NSEvent) { overlay.finish(nil) }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: overlay.finish(nil) // Esc
        case 49: // Space
            dragStart = nil
            dragRect = nil
            overlay.toggleMode()
        default: super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSColor.black.withAlphaComponent(0.32)
        let cutout = dragRect ?? hoveredWindow?.rect
        let path = NSBezierPath(rect: bounds)
        if let cutout {
            path.append(NSBezierPath(rect: cutout))
            path.windingRule = .evenOdd
        }
        dim.setFill()
        path.fill()

        if let rect = dragRect {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1
            border.stroke()
            label("\(Int(rect.width)) × \(Int(rect.height))", below: rect)
        } else if let rect = hoveredWindow?.rect {
            NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.18).setFill()
            NSBezierPath(rect: rect).fill()
            NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.9).setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()
        } else if overlay.currentMode == .area, let pointer {
            // Crosshair lines through the pointer, to line up the first corner.
            NSColor.white.withAlphaComponent(0.35).setStroke()
            let lines = NSBezierPath()
            lines.move(to: CGPoint(x: 0, y: pointer.y)); lines.line(to: CGPoint(x: bounds.width, y: pointer.y))
            lines.move(to: CGPoint(x: pointer.x, y: 0)); lines.line(to: CGPoint(x: pointer.x, y: bounds.height))
            lines.lineWidth = 1
            lines.stroke()
        }

        if pointer != nil || window?.isKeyWindow == true { drawHint() }
    }

    /// The size of the area, in a small pill under it (or inside, at the bottom of the screen).
    private func label(_ text: String, below rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var pill = CGRect(x: rect.midX - size.width / 2 - 8, y: rect.maxY + 6, width: size.width + 16, height: size.height + 6)
        if pill.maxY > bounds.height - 4 { pill.origin.y = rect.maxY - pill.height - 6 }
        pill.origin.x = min(max(pill.minX, 4), bounds.width - pill.width - 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + 8, y: pill.minY + 3), withAttributes: attributes)
    }

    /// What to do, at the top of the screen.
    private func drawHint() {
        let text = overlay.hintText
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let top = bounds.height - screen.visibleFrame.maxY + screen.frame.minY
        let pill = CGRect(x: bounds.midX - size.width / 2 - 14, y: max(top, 0) + 16, width: size.width + 28, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + 14, y: pill.minY + 6), withAttributes: attributes)
    }
}
