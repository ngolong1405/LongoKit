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

    /// What a toolbar under an adjustable area can ask for.
    enum Command { case start, cancel, wholeScreen }

    /// For recordings: the dragged area stays on screen to move and resize, with a toolbar under it that starts it.
    struct Adjusting {
        /// What to do, shown at the top while the area is being adjusted.
        let hint: String
        /// Makes the toolbar (a view of a fixed size); it sends its buttons' commands back.
        let toolbar: (@escaping (Command) -> Void) -> (NSView, CGSize)
    }

    private static var current: SelectionOverlay?

    /// The last pick's panels, kept for a moment after it's done: the drawing editor replaces them in the same frame
    /// (no gap, nothing fading across the screen), or they go a moment later. Their views point back to the overlay,
    /// so it's kept with them.
    private static var lingering: (panels: [OverlayPanel], overlay: SelectionOverlay)?

    /// Takes the last pick's panels off screen now.
    static func dismissLingering() {
        lingering?.panels.forEach { $0.orderOut(nil) }
        lingering = nil
    }

    private var panels: [OverlayPanel] = []
    private var views: [OverlayView] = []
    private var mode: Mode
    private let hint: String
    private let allowsWindows: Bool
    /// Return and a double click take the whole screen.
    fileprivate let allowsScreen: Bool
    fileprivate let adjusting: Adjusting?
    /// Picking an area also picks windows: the window under the pointer lights up, and a click (not a drag) takes it.
    fileprivate let windowsOnClick: Bool
    private let completion: (Selection?) -> Void
    /// On-screen windows of other apps, front to back, in global top-left coordinates.
    private let windows: [(id: CGWindowID, frame: CGRect)]
    /// Each screen as it was when the shortcut was pressed, shown under the overlay (empty: the live screen shows).
    private var frozen: [CGDirectDisplayID: CGImage]
    /// The layer each screen's frozen picture goes in; it can arrive after the overlay is up.
    private var backdrops: [CGDirectDisplayID: NSView] = [:]
    /// The screen whose area is being adjusted, and the toolbar under it.
    private weak var adjustingView: OverlayView?
    private var toolbar: NSPanel?

    /// Whether a pick is under way.
    static var isPicking: Bool { current != nil }

    /// The screens as frozen when the shortcut was pressed, arriving after the overlay is already up.
    static func supply(_ frozen: [CGDirectDisplayID: (image: CGImage, scale: CGFloat)]) {
        guard let current else { return }
        for (display, still) in frozen {
            current.frozen[display] = still.image
            current.backdrops[display]?.layer?.contents = still.image
        }
    }

    /// Cancels the pick under way (for the drawing test).
    static func cancel() { current?.finish(nil) }

    /// Starts picking; `completion` gets nil when it's cancelled. Picking again while picking does nothing.
    static func pick(_ mode: Mode, hint: String, allowsWindows: Bool = true, allowsScreen: Bool = false,
                     adjusting: Adjusting? = nil, windowsOnClick: Bool = false,
                     frozen: [CGDirectDisplayID: (image: CGImage, scale: CGFloat)] = [:], completion: @escaping (Selection?) -> Void) {
        guard current == nil else { return }
        let overlay = SelectionOverlay(mode: mode, hint: hint, allowsWindows: allowsWindows, allowsScreen: allowsScreen,
                                       adjusting: adjusting, windowsOnClick: windowsOnClick, frozen: frozen, completion: completion)
        current = overlay
        overlay.show()
    }

    private init(mode: Mode, hint: String, allowsWindows: Bool, allowsScreen: Bool, adjusting: Adjusting?,
                 windowsOnClick: Bool = false, frozen: [CGDirectDisplayID: (image: CGImage, scale: CGFloat)] = [:],
                 completion: @escaping (Selection?) -> Void) {
        self.windowsOnClick = windowsOnClick
        self.frozen = frozen.mapValues(\.image)
        self.mode = mode
        self.hint = hint
        self.allowsWindows = allowsWindows
        self.allowsScreen = allowsScreen
        self.adjusting = adjusting
        self.completion = completion
        windows = Self.visibleWindows()
    }

    private func show() {
        let pointer = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let panel = OverlayPanel(screen: screen)
            let view = OverlayView(overlay: self, screen: screen)
            // The frozen screen is a layer set once under the overlay: the overlay redraws as the pointer moves, the
            // picture doesn't. It may come a moment after the overlay (see `supply`); until then the live screen shows,
            // which looks the same.
            let backdrop = NSView(frame: view.frame)
            backdrop.wantsLayer = true
            backdrop.layer?.contents = frozen[screen.displayID]
            backdrop.layer?.contentsGravity = .resize
            // The dimming goes under the view (its grips and corners sit on top of it, undimmed).
            let shade = FlippedView(frame: view.frame)
            shade.wantsLayer = true
            backdrop.addSubview(shade)
            backdrop.addSubview(view)
            view.installLayers(shade: shade.layer!)
            panel.contentView = backdrop
            backdrops[screen.displayID] = backdrop
            views.append(view)
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
    fileprivate var hintText: String { adjustingView != nil ? adjusting?.hint ?? hint : hint }

    fileprivate func toggleMode() {
        guard allowsWindows else { return }
        stopAdjusting()
        mode = mode == .area ? .window : .area
        refresh()
    }

    fileprivate func refresh() {
        for view in views { view.update() }
    }

    /// The frontmost window under a point (global top-left coordinates).
    fileprivate func window(at point: CGPoint) -> (id: CGWindowID, frame: CGRect)? {
        windows.first { $0.frame.contains(point) }
    }

    // MARK: - Adjusting

    /// An area was dragged on `view`'s screen: keep it there to adjust, with the toolbar.
    fileprivate func beginAdjusting(_ view: OverlayView, rect: CGRect) {
        guard let adjusting else { return }
        for other in views { other.dropArea(except: view) }
        adjustingView = view
        if toolbar == nil {
            let (content, size) = adjusting.toolbar { [weak self] command in self?.run(command) }
            let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.identifier = Capturer.panelID
            // Up and gone at once: no zoom from macOS.
            panel.animationBehavior = .none
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.contentView = content
            toolbar = panel
        }
        moveToolbar(view, rect: rect)
        toolbar?.orderFrontRegardless()
        refresh()
    }

    /// Under the area, or above it near the bottom of the screen, or inside it when it fills the screen.
    fileprivate func moveToolbar(_ view: OverlayView, rect: CGRect) {
        guard let toolbar, let screen = view.window?.screen else { return }
        let size = toolbar.frame.size
        let frame = screen.frame
        var origin = CGPoint(x: frame.minX + rect.midX - size.width / 2, y: frame.maxY - rect.maxY - 10 - size.height)
        if origin.y < screen.visibleFrame.minY { origin.y = frame.maxY - rect.minY + 10 }
        if origin.y + size.height > screen.visibleFrame.maxY { origin.y = frame.maxY - rect.maxY + 16 }
        origin.x = min(max(origin.x, frame.minX + 8), frame.maxX - size.width - 8)
        toolbar.setFrameOrigin(origin)
    }

    fileprivate func stopAdjusting() {
        adjustingView?.dropArea(except: nil)
        adjustingView = nil
        toolbar?.orderOut(nil)
    }

    private func run(_ command: Command) {
        switch command {
        case .start:
            if let view = adjustingView, let selection = view.adjustedSelection { finish(selection) }
        case .cancel:
            finish(nil)
        case .wholeScreen:
            let screen = adjustingView?.window?.screen ?? Capturer.screenUnderPointer() ?? NSScreen.main!
            finish(.area(display: screen.displayID, rect: .null, scale: screen.backingScaleFactor))
        }
    }

    /// A click on a window waits for a possible second click, which takes the whole screen instead.
    private var pendingWindow: DispatchWorkItem?

    fileprivate func pickWindowSoon(_ id: CGWindowID) {
        pendingWindow?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finish(.window(id)) }
        pendingWindow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + min(NSEvent.doubleClickInterval, 0.3), execute: work)
    }

    fileprivate func finish(_ selection: Selection?) {
        pendingWindow?.cancel()
        pendingWindow = nil
        guard Self.current === self else { return }
        toolbar?.orderOut(nil)
        toolbar = nil
        let closing = panels
        // The views point back here (unowned): they stop following the pointer now, and this overlay is kept with them
        // until they're off screen.
        for view in views { view.trackingAreas.forEach(view.removeTrackingArea) }
        for panel in closing { panel.ignoresMouseEvents = true }
        panels.removeAll()
        views.removeAll()
        NSCursor.pop()
        Self.current = nil
        Self.dismissLingering()
        Self.lingering = (closing, self)
        completion(selection)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if let self, Self.lingering?.overlay === self { Self.dismissLingering() }
        }
    }

    private static func visibleWindows() -> [(id: CGWindowID, frame: CGRect)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let me = getpid()
        // The app's own real windows (its settings) can be picked too; its panels can't.
        let mine = Capturer.ownWindows
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  ((info[kCGWindowAlpha as String] as? Double) ?? 1) > 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != me || mine.contains(id),
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
        identifier = Capturer.panelID
        // Up and gone at once: no zoom from macOS.
        animationBehavior = .none
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
    /// The eight grips of an adjustable area.
    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    private enum Drag {
        case select(from: CGPoint)
        case move(from: CGPoint, original: CGRect)
        case resize(Handle, original: CGRect)
    }

    /// Weak: the overlay goes as soon as a pick is done, and AppKit can still draw or send an event to this view after.
    /// Every way in (drawing, the pointer, keys) checks it's still there; inside, `overlay` is then safe to use.
    private weak var owner: SelectionOverlay?
    private var overlay: SelectionOverlay { owner! }
    private let screen: NSScreen
    /// Where this screen sits in global top-left coordinates (the ones window frames use).
    private let origin: CGPoint
    private var drag: Drag?
    /// The area being dragged out, or (for recordings) the one left on screen to adjust.
    private var area: CGRect?
    private var adjusting = false
    private var pointer: CGPoint?

    /// Live, everything that follows the pointer is a layer moved in place: the dimming (four plain layers around the
    /// cutout), the glowing edge, the size pill and the crosshair. The view itself only draws what changes now and
    /// then (the hint; an adjustable area's corners and grips), so dragging an area out keeps up with the pointer.
    /// Snapshots draw it all in `draw`.
    private var layered = false
    private let dims = (0..<4).map { _ in CALayer() }
    private let edge = CALayer()
    private let lines = (across: CALayer(), down: CALayer())
    private let pill = CALayer()
    private let dot = CALayer()
    private let pillText = CATextLayer()
    /// What `draw` last drew, to draw again only when it changes.
    private struct Drawn: Equatable {
        var adjustable: CGRect?
        var moving: Bool
        var hint: String?
    }
    private var drawn: Drawn?

    init(overlay: SelectionOverlay, screen: NSScreen) {
        owner = overlay
        self.screen = screen
        origin = CGDisplayBounds(screen.displayID).origin
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func installLayers(shade: CALayer) {
        layered = true
        for dim in dims { shade.addSublayer(dim) }
        wantsLayer = true
        let root = layer!
        edge.shadowColor = Self.solar.cgColor
        edge.shadowOffset = .zero
        edge.borderColor = Self.solar.cgColor
        lines.across.backgroundColor = NSColor.white.withAlphaComponent(0.35).cgColor
        lines.down.backgroundColor = lines.across.backgroundColor
        pill.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 0.88).cgColor
        pill.borderColor = Self.solar.withAlphaComponent(0.5).cgColor
        pill.borderWidth = 1
        dot.backgroundColor = Self.solar.cgColor
        dot.cornerRadius = 3
        pill.addSublayer(dot)
        let font = Self.labelAttributes[.font] as! NSFont
        pillText.font = font
        pillText.fontSize = font.pointSize
        pillText.foregroundColor = NSColor.white.cgColor
        pillText.contentsScale = screen.backingScaleFactor
        pill.addSublayer(pillText)
        for layer in [edge, lines.across, lines.down, pill] { root.addSublayer(layer) }
        update()
    }

    /// Shows the current state: layers moved at once, the view drawn again only if what it draws changed.
    func update() {
        guard owner != nil else { return }
        guard layered else { needsDisplay = true; return }
        place()
        let hinted = pointer != nil || window?.isKeyWindow == true
        let now = Drawn(adjustable: adjusting ? area : nil, moving: adjusting && drag != nil, hint: hinted ? overlay.hintText : nil)
        if now != drawn {
            drawn = now
            needsDisplay = true
        }
    }

    private func place() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let window = area == nil ? hoveredWindow?.rect : nil
        let color = NSColor.black.withAlphaComponent(adjusting ? 0.45 : 0.32).cgColor
        for dim in dims { dim.backgroundColor = color }
        if let cut = (area ?? window)?.intersection(bounds), !cut.isNull {
            dims[0].frame = CGRect(x: 0, y: 0, width: bounds.width, height: cut.minY)
            dims[1].frame = CGRect(x: 0, y: cut.maxY, width: bounds.width, height: bounds.height - cut.maxY)
            dims[2].frame = CGRect(x: 0, y: cut.minY, width: cut.minX, height: cut.height)
            dims[3].frame = CGRect(x: cut.maxX, y: cut.minY, width: bounds.width - cut.maxX, height: cut.height)
        } else {
            dims[0].frame = bounds
            for dim in dims.dropFirst() { dim.frame = .zero }
        }

        // The glowing Solar Amber edge, around the area or the window under the pointer.
        if let rect = area {
            frameEdge(rect.insetBy(dx: -1.5, dy: -1.5), width: 1.5, glow: adjusting ? 5 : 3, opacity: 0.8)
        } else if let rect = window {
            frameEdge(rect, width: 2, glow: 4, opacity: 0.7)
        } else {
            edge.isHidden = true
        }

        // Crosshair lines through the pointer, to line up the first corner.
        let crosshair = area == nil && window == nil && overlay.currentMode == .area ? pointer : nil
        lines.across.isHidden = crosshair == nil
        lines.down.isHidden = crosshair == nil
        if let crosshair {
            lines.across.frame = CGRect(x: 0, y: crosshair.y - 0.5, width: bounds.width, height: 1)
            lines.down.frame = CGRect(x: crosshair.x - 0.5, y: 0, width: 1, height: bounds.height)
        }

        // The size, under the area (above it while adjusting, where the toolbar is under it).
        pill.isHidden = area == nil
        if let rect = area {
            let text = "\(Int(rect.width)) × \(Int(rect.height))"
            let size = (text as NSString).size(withAttributes: Self.labelAttributes)
            var label = CGRect(x: rect.midX - size.width / 2 - 8, y: 0, width: size.width + 16, height: size.height + 6)
            if adjusting {
                label.origin.y = rect.minY - size.height - 12
                if label.minY < 4 { label.origin.y = rect.minY + 6 }
            } else {
                label.origin.y = rect.maxY + 6
                if label.maxY > bounds.height - 4 { label.origin.y = rect.maxY - label.height - 6 }
            }
            var frame = label.insetBy(dx: -6, dy: -2)
            frame.size.width += 6
            frame.origin.x = min(max(frame.minX, 4), bounds.width - frame.width - 4)
            if pill.bounds.size != frame.size {
                pill.cornerRadius = frame.height / 2
                dot.frame = CGRect(x: 7, y: frame.height / 2 - 3, width: 6, height: 6)
                pillText.frame = CGRect(x: 22, y: (frame.height - size.height) / 2, width: size.width + 2, height: size.height)
            }
            pill.frame = frame
            if pillText.string as? String != text { pillText.string = text }
        }
    }

    private func frameEdge(_ frame: CGRect, width: CGFloat, glow: CGFloat, opacity: Float) {
        edge.isHidden = false
        if edge.bounds.size != frame.size || edge.borderWidth != width {
            edge.bounds = CGRect(origin: .zero, size: frame.size)
            edge.borderWidth = width
            // Just the line glows: its outline, not the inside.
            edge.shadowPath = CGPath(rect: edge.bounds.insetBy(dx: width / 2, dy: width / 2), transform: nil)
                .copy(strokingWithWidth: width, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        }
        edge.shadowRadius = glow
        edge.shadowOpacity = opacity
        edge.position = CGPoint(x: frame.midX, y: frame.midY)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func local(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    /// The adjusted area as a selection, for Start.
    var adjustedSelection: Selection? {
        guard adjusting, let rect = area?.integral else { return nil }
        return .area(display: screen.displayID, rect: rect, scale: screen.backingScaleFactor)
    }

    /// For snapshots: an adjustable area, as if being moved when `dragging`.
    func showAdjusting(_ rect: CGRect, dragging: Bool) {
        area = rect
        adjusting = true
        drag = dragging ? .move(from: .zero, original: rect) : nil
    }

    /// Another screen got the area (or adjusting stopped): this one goes back to plain picking.
    func dropArea(except keep: OverlayView?) {
        guard keep !== self else { return }
        area = nil
        adjusting = false
        drag = nil
        update()
    }

    /// The highlighted window, in this view's coordinates.
    private var hoveredWindow: (id: CGWindowID, rect: CGRect)? {
        let idle: Bool = { if case .select = drag { return (area?.width ?? 0) < 4 }; return drag == nil && area == nil }()
        guard overlay.currentMode == .window || (overlay.windowsOnClick && idle && !adjusting), let pointer else { return nil }
        let global = CGPoint(x: pointer.x + origin.x, y: pointer.y + origin.y)
        guard let window = overlay.window(at: global) else { return nil }
        return (window.id, window.frame.offsetBy(dx: -origin.x, dy: -origin.y))
    }

    private func point(of handle: Handle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    /// Corners take a generous square around them; edges, their grip and the edge itself.
    private func handle(at point: CGPoint) -> Handle? {
        guard adjusting, let area else { return nil }
        let corners: [Handle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
        if let corner = corners.first(where: { let c = self.point(of: $0, in: area); return abs(c.x - point.x) <= 14 && abs(c.y - point.y) <= 14 }) {
            return corner
        }
        let near: CGFloat = 6
        if abs(point.y - area.minY) <= near, point.x > area.minX, point.x < area.maxX { return .top }
        if abs(point.y - area.maxY) <= near, point.x > area.minX, point.x < area.maxX { return .bottom }
        if abs(point.x - area.minX) <= near, point.y > area.minY, point.y < area.maxY { return .left }
        if abs(point.x - area.maxX) <= near, point.y > area.minY, point.y < area.maxY { return .right }
        return nil
    }

    private func cursor(for point: CGPoint) -> NSCursor {
        guard adjusting, let area else { return .crosshair }
        if let handle = handle(at: point) {
            switch handle {
            case .left, .right: return .resizeLeftRight
            case .top, .bottom: return .resizeUpDown
            default:
                if #available(macOS 15.0, *) {
                    let position: NSCursor.FrameResizePosition = switch handle {
                    case .topLeft: .topLeft
                    case .topRight: .topRight
                    case .bottomLeft: .bottomLeft
                    default: .bottomRight
                    }
                    return .frameResize(position: position, directions: .all)
                }
                return .crosshair
            }
        }
        return area.contains(point) ? .openHand : .crosshair
    }

    override func mouseMoved(with event: NSEvent) {
        guard owner != nil else { return }
        pointer = local(event)
        if !(window?.isKeyWindow ?? false) { window?.makeKey(); window?.makeFirstResponder(self) }
        cursor(for: pointer!).set()
        overlay.refresh()
    }

    override func mouseExited(with event: NSEvent) {
        guard owner != nil else { return }
        pointer = nil
        update()
    }

    override func mouseDown(with event: NSEvent) {
        guard owner != nil else { return }
        let point = local(event)
        if overlay.currentMode == .window {
            pointer = point
            if let hovered = hoveredWindow { overlay.finish(.window(hovered.id)) }
            return
        }
        // A double click takes the whole screen.
        if event.clickCount >= 2, overlay.allowsScreen {
            return overlay.finish(.area(display: screen.displayID, rect: .null, scale: screen.backingScaleFactor))
        }
        if adjusting, let area {
            if let handle = handle(at: point) {
                drag = .resize(handle, original: area)
                return
            }
            if area.contains(point) {
                drag = .move(from: point, original: area)
                NSCursor.closedHand.set()
                return
            }
            // Outside: start over with a new area.
            overlay.stopAdjusting()
        }
        drag = .select(from: point)
        area = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard owner != nil else { return }
        let point = local(event)
        pointer = point
        switch drag {
        case let .select(start):
            area = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
        case let .move(start, original):
            var moved = original.offsetBy(dx: point.x - start.x, dy: point.y - start.y)
            moved.origin.x = min(max(moved.minX, 0), bounds.width - moved.width)
            moved.origin.y = min(max(moved.minY, 0), bounds.height - moved.height)
            area = moved
        case let .resize(handle, original):
            area = resized(original, handle: handle, to: point)
        case nil:
            return
        }
        if adjusting, let area { overlay.moveToolbar(self, rect: area) }
        update()
    }

    /// `original` with the edges `handle` holds moved to `point`; it can be dragged past the opposite edge.
    private func resized(_ original: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
        var minX = original.minX, maxX = original.maxX, minY = original.minY, maxY = original.maxY
        switch handle {
        case .topLeft: (minX, minY) = (point.x, point.y)
        case .top: minY = point.y
        case .topRight: (maxX, minY) = (point.x, point.y)
        case .right: maxX = point.x
        case .bottomRight: (maxX, maxY) = (point.x, point.y)
        case .bottom: maxY = point.y
        case .bottomLeft: (minX, maxY) = (point.x, point.y)
        case .left: minX = point.x
        }
        let rect = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
        return CGRect(x: rect.minX, y: rect.minY, width: max(rect.width, 16), height: max(rect.height, 16))
    }

    override func mouseUp(with event: NSEvent) {
        guard owner != nil else { return }
        defer {
            drag = nil
            update()
        }
        guard case .select = drag else {
            if let pointer { cursor(for: pointer).set() }
            return
        }
        guard let rect = area?.integral, rect.width >= 4, rect.height >= 4 else {
            area = nil
            update()
            // A click, not a drag: the window under it.
            if overlay.windowsOnClick, let hovered = hoveredWindow { overlay.pickWindowSoon(hovered.id) }
            return
        }
        if overlay.adjusting != nil {
            area = rect
            adjusting = true
            overlay.beginAdjusting(self, rect: rect)
        } else {
            overlay.finish(.area(display: screen.displayID, rect: rect, scale: screen.backingScaleFactor))
        }
    }

    override func rightMouseDown(with event: NSEvent) { owner?.finish(nil) }

    override func keyDown(with event: NSEvent) {
        guard owner != nil else { return }
        switch Int(event.keyCode) {
        case 53: overlay.finish(nil) // Esc
        case 49: // Space
            drag = nil
            area = nil
            overlay.toggleMode()
        case 36, 76: // Return, Enter: start the adjusted area, or take the screen under the pointer
            if let selection = overlay.adjusting != nil ? overlay.adjustedSelectionAnywhere : nil {
                overlay.finish(selection)
            } else if overlay.allowsScreen {
                let screen = Capturer.screenUnderPointer() ?? self.screen
                overlay.finish(.area(display: screen.displayID, rect: .null, scale: screen.backingScaleFactor))
            }
        default: super.keyDown(with: event)
        }
    }

    /// LongoKit's Solar Amber.
    private static let solar = NSColor(red: 1, green: 0.42, blue: 0.21, alpha: 1)

    override func draw(_ dirtyRect: NSRect) {
        guard owner != nil else { return }
        if layered {
            if adjusting, let area { drawAdjusting(area) }
        } else {
            drawAll()
        }
        if pointer != nil || window?.isKeyWindow == true { drawHint() }
    }

    /// Everything, for snapshots (live, the layers show most of it).
    private func drawAll() {
        // A little darker while adjusting, so the area stands out.
        let dim = NSColor.black.withAlphaComponent(adjusting ? 0.45 : 0.32)
        let cutout = area ?? hoveredWindow?.rect
        let path = NSBezierPath(rect: bounds)
        if let cutout {
            path.append(NSBezierPath(rect: cutout))
            path.windingRule = .evenOdd
        }
        dim.setFill()
        path.fill()

        if let rect = area {
            drawFrame(rect)
            if adjusting {
                // The toolbar sits under the area, so the size goes above it.
                label("\(Int(rect.width)) × \(Int(rect.height))", above: rect)
            } else {
                label("\(Int(rect.width)) × \(Int(rect.height))", below: rect)
            }
        } else if let rect = hoveredWindow?.rect {
            // The window is left undimmed, with the same glowing Solar Amber edge as an area.
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = Self.solar.withAlphaComponent(0.7)
            glow.shadowBlurRadius = 8
            glow.set()
            Self.solar.setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()
            NSGraphicsContext.restoreGraphicsState()
        } else if overlay.currentMode == .area, let pointer {
            // Crosshair lines through the pointer, to line up the first corner.
            NSColor.white.withAlphaComponent(0.35).setStroke()
            let lines = NSBezierPath()
            lines.move(to: CGPoint(x: 0, y: pointer.y)); lines.line(to: CGPoint(x: bounds.width, y: pointer.y))
            lines.move(to: CGPoint(x: pointer.x, y: 0)); lines.line(to: CGPoint(x: pointer.x, y: bounds.height))
            lines.lineWidth = 1
            lines.stroke()
        }
    }

    /// The area's frame in the LongoKit look: a glowing Solar Amber edge; while adjusting, viewfinder corners like
    /// the app icon, a grip in the middle of each side, and thirds while it's being moved or resized.
    private func drawFrame(_ rect: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = Self.solar.withAlphaComponent(0.8)
        glow.shadowBlurRadius = adjusting ? 10 : 6
        glow.set()
        Self.solar.setStroke()
        let edge = NSBezierPath(rect: rect.insetBy(dx: -0.75, dy: -0.75))
        edge.lineWidth = 1.5
        edge.stroke()
        NSGraphicsContext.restoreGraphicsState()
        if adjusting { drawAdjusting(rect) }
    }

    /// An adjustable area's viewfinder corners and side grips, and thirds while it's moved or resized.
    private func drawAdjusting(_ rect: CGRect) {
        if drag != nil {
            NSColor.white.withAlphaComponent(0.22).setStroke()
            let thirds = NSBezierPath()
            for i in 1...2 {
                let x = rect.minX + rect.width * CGFloat(i) / 3, y = rect.minY + rect.height * CGFloat(i) / 3
                thirds.move(to: CGPoint(x: x, y: rect.minY)); thirds.line(to: CGPoint(x: x, y: rect.maxY))
                thirds.move(to: CGPoint(x: rect.minX, y: y)); thirds.line(to: CGPoint(x: rect.maxX, y: y))
            }
            thirds.lineWidth = 1
            thirds.stroke()
        }

        // Corners: an L just outside each corner, white over a dark edge so it shows on any background.
        let length = min(22, rect.width / 3, rect.height / 3)
        let corners = NSBezierPath()
        for (x, y, dx, dy) in [(rect.minX, rect.minY, 1.0, 1.0), (rect.maxX, rect.minY, -1.0, 1.0),
                               (rect.maxX, rect.maxY, -1.0, -1.0), (rect.minX, rect.maxY, 1.0, -1.0)] {
            let cx = x - 2 * dx, cy = y - 2 * dy
            corners.move(to: CGPoint(x: cx, y: cy + length * dy))
            corners.line(to: CGPoint(x: cx, y: cy))
            corners.line(to: CGPoint(x: cx + length * dx, y: cy))
        }
        corners.lineCapStyle = .round
        corners.lineJoinStyle = .round
        // Sides: a short rounded grip across the middle of each edge.
        var grips: [NSBezierPath] = []
        if rect.width > 70 {
            for y in [rect.minY, rect.maxY] {
                grips.append(NSBezierPath(roundedRect: CGRect(x: rect.midX - 12, y: y - 3, width: 24, height: 6), xRadius: 3, yRadius: 3))
            }
        }
        if rect.height > 70 {
            for x in [rect.minX, rect.maxX] {
                grips.append(NSBezierPath(roundedRect: CGRect(x: x - 3, y: rect.midY - 12, width: 6, height: 24), xRadius: 3, yRadius: 3))
            }
        }
        NSColor.black.withAlphaComponent(0.4).setStroke()
        corners.lineWidth = 6.5
        corners.stroke()
        for grip in grips { grip.lineWidth = 2.5; grip.stroke() }
        NSColor.white.setStroke()
        corners.lineWidth = 4
        corners.stroke()
        NSColor.white.setFill()
        for grip in grips { grip.fill() }
    }

    /// The size of the area, in a small pill under it (or inside, at the bottom of the screen).
    private func label(_ text: String, below rect: CGRect) {
        let size = (text as NSString).size(withAttributes: Self.labelAttributes)
        var pill = CGRect(x: rect.midX - size.width / 2 - 8, y: rect.maxY + 6, width: size.width + 16, height: size.height + 6)
        if pill.maxY > bounds.height - 4 { pill.origin.y = rect.maxY - pill.height - 6 }
        drawPill(text, pill)
    }

    /// The size of an adjustable area, above it (or inside, at the top of the screen).
    private func label(_ text: String, above rect: CGRect) {
        let size = (text as NSString).size(withAttributes: Self.labelAttributes)
        var pill = CGRect(x: rect.midX - size.width / 2 - 8, y: rect.minY - size.height - 12, width: size.width + 16, height: size.height + 6)
        if pill.minY < 4 { pill.origin.y = rect.minY + 6 }
        drawPill(text, pill)
    }

    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: "JetBrains Mono", size: 11) ?? NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    /// A dark pill with a Solar Amber dot, like the app's chips.
    private func drawPill(_ text: String, _ rect: CGRect) {
        var pill = rect.insetBy(dx: -6, dy: -2)
        pill.size.width += 6
        pill.origin.x = min(max(pill.minX, 4), bounds.width - pill.width - 4)
        NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 0.88).setFill()
        let shape = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
        shape.fill()
        Self.solar.withAlphaComponent(0.5).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        Self.solar.setFill()
        NSBezierPath(ovalIn: CGRect(x: pill.minX + 10, y: pill.midY - 3, width: 6, height: 6)).fill()
        let size = (text as NSString).size(withAttributes: Self.labelAttributes)
        (text as NSString).draw(at: CGPoint(x: pill.minX + 22, y: pill.midY - size.height / 2), withAttributes: Self.labelAttributes)
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

extension SelectionOverlay {
    /// The adjusted area, whichever screen it's on (Return can be pressed with the pointer on another screen).
    fileprivate var adjustedSelectionAnywhere: Selection? { adjustingView?.adjustedSelection }
}

extension SelectionOverlay {
    /// The adjustable frame drawn over `background` (a picture the size of the main screen), for snapshots.
    static func preview(over background: NSImage, area: CGRect, dragging: Bool) -> NSImage? {
        guard let screen = NSScreen.main else { return nil }
        let overlay = SelectionOverlay(mode: .area, hint: "", allowsWindows: false, allowsScreen: true, adjusting: nil) { _ in }
        let view = OverlayView(overlay: overlay, screen: screen)
        view.showAdjusting(area, dragging: dragging)
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        background.draw(in: CGRect(origin: .zero, size: size))
        // The view draws top-down: a flipped context over the same pixels, as the screen gives it.
        context.cgContext.translateBy(x: 0, y: size.height)
        context.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}

/// A plain view with its origin at the top-left, like the overlay's.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
