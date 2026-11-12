import AppKit
import LongoKitUI
import SwiftUI

/// Drawing on an area right after it's captured, where it was on screen: the picture stays in place over a dimmed
/// screen with the drawing toolbar under it. Done hands back the picture with its marks to save and copy as set; ⌘C,
/// to save and copy whatever the clipboard setting; Esc goes back to picking the area; ✕, nothing. With the whole screen at hand (an
/// area or the screen), the area can still be resized from its eight grips and moved by its edges while drawing.
@MainActor
final class InPlaceEditor {
    enum Outcome {
        case save(CGImage)
        case saveAndCopy(CGImage)
        /// Esc: back to picking the area, on the same frozen screens.
        case pickAgain
        case discard
    }

    private static var current: InPlaceEditor?

    /// How dark the screen around the area is: the selection overlay's, so nothing jumps between the two.
    static let dim = 0.32

    /// Captures wait until the open editor is done.
    static var isOpen: Bool { current != nil }

    /// The editor's frame on screen, for the drawing test.
    static var frame: CGRect? { current?.panel?.frame }

    /// What the editor shows, for the drawing test.
    static var view: NSView? { current?.panel?.contentView }

    /// The area being drawn on, in points from the screen's top-left, when it can be adjusted. Setting it is what
    /// dragging the area does (for the drawing test).
    static var area: CGRect? {
        get { current?.adjustable?.rect }
        set { if let newValue { current?.adjustable?.rect = newValue } }
    }

    /// The drawing tool picked (none: dragging moves the area).
    static var tool: Mark.Tool? { current?.state.tool }

    /// Finishes as the toolbar's buttons and keys do (for the drawing test).
    static func finish(_ result: Annotator.Result) { current?.finish(result) }

    /// The adjustable area, published for the view.
    final class Area: ObservableObject {
        @Published var rect: CGRect
        init(_ rect: CGRect) { self.rect = rect }
    }

    static func cancel() { current?.close(with: .discard) }

    private let image: CGImage
    /// Set when `image` is the whole screen and the area can be adjusted; the picture is cut from it at the end.
    private var adjustable: Area?
    private let state: AnnotationState
    private let completion: (Outcome) -> Void
    private var backdrops: [NSPanel] = []
    private var panel: NSPanel?

    /// `area` is in points from the screen's top-left; `.null` for the whole screen.
    static func open(_ image: CGImage, scale: CGFloat, on screen: NSScreen, area: CGRect, completion: @escaping (Outcome) -> Void) {
        current?.close(with: .discard)
        let editor = InPlaceEditor(image: image, scale: scale, completion: completion)
        current = editor
        editor.show(on: screen, area: area.isNull ? CGRect(origin: .zero, size: screen.frame.size) : area)
    }

    /// `screenImage` is the whole screen (as it was when the shortcut was pressed); `area` is in points from its
    /// top-left, `.null` for all of it. The area can be resized and moved while drawing.
    static func open(screen screenImage: CGImage, scale: CGFloat, on screen: NSScreen, area: CGRect,
                     completion: @escaping (Outcome) -> Void) {
        current?.close(with: .discard)
        let editor = InPlaceEditor(image: screenImage, scale: scale, completion: completion)
        current = editor
        editor.showAdjustable(on: screen, area: area.isNull ? CGRect(origin: .zero, size: screen.frame.size) : area)
    }

    private static var measuredToolbar: (AppLanguage, CGSize)?

    /// The drawing toolbar's size, measured once per language rather than on every capture.
    private static func toolbarSize(_ state: AnnotationState) -> CGSize {
        if let (language, size) = measuredToolbar, language == Localizer.language { return size }
        let size = NSHostingView(rootView: DrawToolbar(state: state) { _ in }).fittingSize
        measuredToolbar = (Localizer.language, size)
        return size
    }

    private init(image: CGImage, scale: CGFloat, completion: @escaping (Outcome) -> Void) {
        self.image = image
        state = AnnotationState(pixelsPerPoint: scale)
        self.completion = completion
    }

    private func show(on screen: NSScreen, area rect: CGRect) {
        // Every screen dims; on this one the captured area stays clear.
        for other in NSScreen.screens {
            let backdrop = Self.panel(other.frame, level: .screenSaver)
            backdrop.contentView = Backdrop(frame: CGRect(origin: .zero, size: other.frame.size), clear: other == screen ? rect : nil)
            backdrops.append(backdrop)
        }

        let toolbarSize = Self.toolbarSize(state)
        let layout = Self.layout(area: rect, toolbar: toolbarSize, screen: screen)
        let root = ZStack(alignment: .topLeading) {
            MarkCanvas(image: image, state: state)
                .frame(width: rect.width, height: rect.height)
                .overlay(Rectangle().strokeBorder(Theme.solar.opacity(0.9), lineWidth: 1.5).allowsHitTesting(false))
                .offset(x: rect.minX - layout.frame.minX, y: rect.minY - layout.frame.minY)
            DrawToolbar(state: state) { [weak self] result in self?.finish(result) }
                .offset(x: layout.toolbar.minX - layout.frame.minX, y: layout.toolbar.minY - layout.frame.minY)
        }
        .frame(width: layout.frame.width, height: layout.frame.height, alignment: .topLeading)

        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: layout.frame.size)
        let frame = CGRect(x: screen.frame.minX + layout.frame.minX, y: screen.frame.maxY - layout.frame.maxY,
                           width: layout.frame.width, height: layout.frame.height)
        let panel = Self.panel(frame, level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1))
        panel.contentView = host
        present(panel)
    }

    private func showAdjustable(on screen: NSScreen, area rect: CGRect) {
        // The other screens dim; this one is the editor itself, the area clear and the rest dimmed.
        for other in NSScreen.screens where other != screen {
            let backdrop = Self.panel(other.frame, level: .screenSaver)
            backdrop.contentView = Backdrop(frame: CGRect(origin: .zero, size: other.frame.size), clear: nil)
            backdrops.append(backdrop)
        }
        let area = Area(rect)
        adjustable = area
        // As in iShot: no tool at first, so the area can be dragged elsewhere or resized before copying; picking a tool
        // draws.
        state.tool = nil
        let toolbarSize = Self.toolbarSize(state)
        let view = AdjustableView(image: image, size: screen.frame.size, state: state, area: area, toolbarSize: toolbarSize,
                                  toolbar: { Self.layout(area: $0, toolbar: toolbarSize, screen: screen).toolbar }) { [weak self] result in
            self?.finish(result)
        }
        let panel = Self.panel(screen.frame, level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1))
        // The frozen screen covers it all: nothing under it to blend with.
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.contentView = view
        present(panel)
        // The toolbar takes the keys: tools, ⌘Z, Return, Esc.
        panel.makeFirstResponder(view.toolbarHost)
    }

    /// Puts the editor up in place of the selection overlay as one change on screen: drawn before it's shown, and the
    /// overlay taken down in the same update, so there's no frame with neither, or with both.
    private func present(_ panel: NSPanel) {
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            for backdrop in backdrops { backdrop.orderFrontRegardless() }
            panel.makeKeyAndOrderFront(nil)
            SelectionOverlay.dismissLingering()
        }
        self.panel = panel
    }

    /// Measures the toolbar ahead of the first capture, so opening the editor then has nothing extra to do.
    static func warmUp() {
        _ = toolbarSize(AnnotationState(pixelsPerPoint: 2))
    }

    /// Where the toolbar goes (screen points from the top-left): under the area, else above it, else inside at its
    /// bottom (a whole-screen capture); and the frame holding both.
    private static func layout(area: CGRect, toolbar: CGSize, screen: NSScreen) -> (toolbar: CGRect, frame: CGRect) {
        let gap: CGFloat = 8
        let top = screen.frame.maxY - screen.visibleFrame.maxY
        let bottom = screen.frame.maxY - screen.visibleFrame.minY
        var y = area.maxY + gap
        if y + toolbar.height > bottom {
            y = area.minY - gap - toolbar.height
            // No room outside (a whole-screen capture): inside, just above the Dock.
            if y < top { y = min(area.maxY, bottom) - toolbar.height - 16 }
        }
        let x = min(max(area.midX - toolbar.width / 2, 8), screen.frame.width - toolbar.width - 8)
        let bar = CGRect(x: x, y: y, width: toolbar.width, height: toolbar.height)
        return (bar, area.union(bar).integral)
    }

    private func finish(_ result: Annotator.Result) {
        let marks: [Mark]
        let outcome: (CGImage) -> Outcome
        switch result {
        case let .done(drawn): (marks, outcome) = (drawn, { .save($0) })
        case let .copy(drawn): (marks, outcome) = (drawn, { .saveAndCopy($0) })
        case .cancel: return close(with: .discard)
        case .back: return close(with: .pickAgain)
        }
        // Gone from the screen at once; the picture is drawn at full size off the main thread, then handed on.
        let image = image, area = adjustable?.rect, scale = state.pixelsPerPoint, completion = completion
        dismiss()
        Task { @MainActor in
            let picture = await Task.detached(priority: .userInitiated) {
                Self.picture(image, marks: marks, area: area, scale: scale)
            }.value
            completion(outcome(picture))
        }
    }

    /// The marks drawn onto the capture; with the whole screen at hand, cut to the area as it ended up.
    nonisolated static func picture(_ image: CGImage, marks: [Mark], area: CGRect?, scale: CGFloat) -> CGImage {
        // The area is cut first (sharing the screen's pixels), so only its part is drawn on, not the whole screen.
        let part = area.flatMap { Capturer.cut(image, scale: scale, to: $0) } ?? image
        guard !marks.isEmpty else { return part }
        let origin = area.map { CGPoint(x: ($0.minX * scale).rounded(.down), y: ($0.minY * scale).rounded(.down)) } ?? .zero
        return Mark.render(marks, on: part, origin: origin) ?? part
    }

    private func dismiss() {
        panel?.orderOut(nil)
        for backdrop in backdrops { backdrop.orderOut(nil) }
        panel = nil
        backdrops = []
        if Self.current === self { Self.current = nil }
        NSCursor.arrow.set()
    }

    private func close(with outcome: Outcome) {
        dismiss()
        completion(outcome)
    }

    private static func panel(_ frame: CGRect, level: NSWindow.Level) -> NSPanel {
        let panel = KeyPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.identifier = Capturer.panelID
        // Up and gone at once: no zoom from macOS.
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = level
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    /// Takes keys (tools, ⌘Z, Return, Esc) without bringing the app forward.
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    /// The dimmed screen around the capture; clicks on it do nothing.
    private final class Backdrop: NSView {
        let clear: CGRect?

        init(frame: CGRect, clear: CGRect?) {
            self.clear = clear
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) { fatalError() }

        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {}

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(rect: bounds)
            if let clear {
                path.append(NSBezierPath(rect: clear))
                path.windingRule = .evenOdd
            }
            NSColor.black.withAlphaComponent(InPlaceEditor.dim).setFill()
            path.fill()
        }
    }
}

/// Where an area's grips are.
enum Grip: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var left: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var right: Bool { self == .topRight || self == .right || self == .bottomRight }
    var top: Bool { self == .topLeft || self == .top || self == .topRight }
    var bottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    /// The pointer over this grip: a resize arrow pointing the ways it moves.
    var cursor: NSCursor {
        switch self {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default:
            guard #available(macOS 15.0, *) else { return .crosshair }
            let position: NSCursor.FrameResizePosition = switch self {
            case .topLeft: .topLeft
            case .topRight: .topRight
            case .bottomLeft: .bottomLeft
            default: .bottomRight
            }
            return .frameResize(position: position, directions: .all)
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: left ? rect.minX : right ? rect.maxX : rect.midX, y: top ? rect.minY : bottom ? rect.maxY : rect.midY)
    }

    /// `rect` with this grip dragged by `delta`, kept inside `bounds` and at least 8 pt each way. Dragging past the
    /// opposite edge flips it, as in the capture overlay.
    func resize(_ rect: CGRect, by delta: CGSize, in bounds: CGRect) -> CGRect {
        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        if left { minX += delta.width }
        if right { maxX += delta.width }
        if top { minY += delta.height }
        if bottom { maxY += delta.height }
        var next = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
            .intersection(bounds)
        next.size.width = max(next.width, 8)
        next.size.height = max(next.height, 8)
        return next
    }
}

/// The area moved by `delta`, kept inside `bounds`.
func moved(_ rect: CGRect, by delta: CGSize, in bounds: CGRect) -> CGRect {
    CGRect(x: min(max(rect.minX + delta.width, bounds.minX), bounds.maxX - rect.width),
           y: min(max(rect.minY + delta.height, bounds.minY), bounds.maxY - rect.height),
           width: rect.width, height: rect.height)
}

/// The whole screen as frozen while picking, dimmed around the area, with the area's eight grips and the toolbar.
/// Everything that moves with the area is a layer moved in place (nothing is redrawn while dragging), so moving or
/// resizing it keeps up with the pointer; the marks and the toolbar are SwiftUI, only slid along.
private final class AdjustableView: NSView {
    let toolbarHost: NSView
    private let state: AnnotationState
    private let area: InPlaceEditor.Area
    private let toolbar: (CGRect) -> CGRect
    private let toolbarSize: CGSize
    /// The dimmed screen: four plain layers around the area (top, bottom, left, right), which the GPU just moves,
    /// rather than one shape to fill again over the whole screen.
    private let dims = (0..<4).map { _ in CALayer() }
    private let edge = CALayer()
    private let grips: [CALayer]
    private let sizeLabel = CATextLayer()
    /// Holds the marks canvas, still, over the whole screen; a mask the size of the area shows only its part, and only
    /// the mask moves with the area.
    private let marksHolder = NSView()
    private let marksMask = CALayer()
    /// Holds the toolbar; it's this that moves with the area, so the SwiftUI toolbar inside never changes frame.
    private let toolbarHolder = NSView()
    /// The marks canvas, made when a tool is first picked (most captures are copied without drawing).
    private var marks: NSView?
    private let image: CGImage
    private var watching: [Any] = []
    /// What a drag started on, and the area then.
    private enum Handle { case move, grip(Grip) }
    private var drag: (handle: Handle, start: CGPoint, rect: CGRect)?

    init(image: CGImage, size: CGSize, state: AnnotationState, area: InPlaceEditor.Area, toolbarSize: CGSize,
         toolbar: @escaping (CGRect) -> CGRect, finish: @escaping (Annotator.Result) -> Void) {
        self.state = state
        self.area = area
        self.toolbar = toolbar
        self.toolbarSize = toolbarSize
        let host = NSHostingView(rootView: DrawToolbar(state: state, finish: finish).fixedSize())
        host.sizingOptions = []
        toolbarHost = host
        self.image = image
        grips = Grip.allCases.map { _ in CALayer() }
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        let root = layer!
        let scale = CGFloat(image.width) / max(size.width, 1)

        let picture = CALayer()
        picture.frame = bounds
        picture.contents = image
        picture.contentsGravity = .resize
        root.addSublayer(picture)

        marksHolder.frame = bounds
        marksHolder.wantsLayer = true
        marksMask.backgroundColor = NSColor.black.cgColor
        marksHolder.layer?.mask = marksMask
        addSubview(marksHolder)

        for dim in dims {
            dim.backgroundColor = NSColor.black.withAlphaComponent(InPlaceEditor.dim).cgColor
            dim.zPosition = 1
            root.addSublayer(dim)
        }

        // The same glowing edge as while picking; the glow follows a path, so it isn't worked out from pixels.
        let solar = NSColor(red: 1, green: 0.42, blue: 0.21, alpha: 1).cgColor
        edge.borderColor = solar
        edge.borderWidth = 1.5
        edge.shadowColor = solar
        edge.shadowOpacity = 0.8
        edge.shadowRadius = 3
        edge.shadowOffset = .zero
        edge.zPosition = 2
        root.addSublayer(edge)

        for grip in grips {
            grip.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
            grip.backgroundColor = NSColor.white.cgColor
            grip.borderColor = solar
            grip.borderWidth = 1.5
            grip.cornerRadius = 2.5
            grip.shadowColor = NSColor.black.cgColor
            grip.shadowOpacity = 0.35
            grip.shadowRadius = 2
            grip.shadowOffset = .zero
            grip.shadowPath = CGPath(roundedRect: grip.bounds, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
            grip.zPosition = 3
            root.addSublayer(grip)
        }

        sizeLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        sizeLabel.fontSize = 11
        sizeLabel.foregroundColor = NSColor.white.cgColor
        sizeLabel.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        sizeLabel.alignmentMode = .center
        sizeLabel.contentsScale = scale
        sizeLabel.isHidden = true
        sizeLabel.zPosition = 4
        root.addSublayer(sizeLabel)

        host.frame = CGRect(origin: .zero, size: toolbarSize)
        toolbarHolder.frame = host.frame
        toolbarHolder.addSubview(host)
        addSubview(toolbarHolder)

        place(area.rect)
        // The drawing test (and anything else) setting the area moves it too.
        watching.append(area.$rect.dropFirst().sink { [weak self] rect in self?.place(rect) })
        watching.append(state.$tool.sink { [weak self] tool in if tool != nil { self?.makeMarks() } })
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func makeMarks() {
        guard marks == nil else { return }
        let canvas = NSHostingView(rootView: MarkCanvas(image: image, state: state, showsImage: false)
            .frame(width: bounds.width, height: bounds.height))
        canvas.sizingOptions = []
        canvas.frame = bounds
        marksHolder.addSubview(canvas)
        marks = canvas
    }

    /// Puts everything that follows the area where it now is, without animation.
    private func place(_ rect: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dims[0].frame = CGRect(x: 0, y: 0, width: bounds.width, height: rect.minY)
        dims[1].frame = CGRect(x: 0, y: rect.maxY, width: bounds.width, height: bounds.height - rect.maxY)
        dims[2].frame = CGRect(x: 0, y: rect.minY, width: rect.minX, height: rect.height)
        dims[3].frame = CGRect(x: rect.maxX, y: rect.minY, width: bounds.width - rect.maxX, height: rect.height)
        let outer = rect.insetBy(dx: -1.5, dy: -1.5)
        // Moving keeps the size: then only the position changes, and the glow's path stays as it is.
        if edge.bounds.size != outer.size {
            edge.bounds = CGRect(origin: .zero, size: outer.size)
            // Just the 1.5 pt line, as an outline (two rects in one path would fill the whole area with the glow).
            edge.shadowPath = CGPath(rect: edge.bounds.insetBy(dx: 0.75, dy: 0.75), transform: nil)
                .copy(strokingWithWidth: 1.5, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        }
        edge.position = CGPoint(x: outer.midX, y: outer.midY)
        for (grip, layer) in zip(Grip.allCases, grips) { layer.position = grip.point(in: rect) }
        marksMask.frame = rect
        if !sizeLabel.isHidden {
            let text = "\(Int(rect.width)) × \(Int(rect.height))"
            if sizeLabel.string as? String != text {
                sizeLabel.string = text
                let width = text.size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)]).width + 14
                sizeLabel.bounds = CGRect(x: 0, y: 0, width: width, height: 19)
                sizeLabel.cornerRadius = 9.5
            }
            sizeLabel.position = CGPoint(x: rect.minX + sizeLabel.bounds.width / 2, y: max(rect.minY - 26, 4) + 9.5)
        }
        CATransaction.commit()
        toolbarHolder.setFrameOrigin(toolbar(rect).origin)
    }

    // MARK: Pointer

    /// What's under `point`: a grip, an edge or (with no tool picked) the inside, which move the area.
    private func handle(at point: CGPoint) -> Handle? {
        let rect = area.rect
        for grip in Grip.allCases where hypot(point.x - grip.point(in: rect).x, point.y - grip.point(in: rect).y) <= 11 {
            return .grip(grip)
        }
        let outer = rect.insetBy(dx: -5, dy: -5), inner = rect.insetBy(dx: 5, dy: 5)
        if outer.contains(point) && !inner.contains(point) { return .move }
        if state.tool == nil && rect.contains(point) { return .move }
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if toolbarHolder.frame.contains(local) { return super.hitTest(point) }
        // A tool picked: inside the area is the marks' (but the grips and edges still adjust it).
        if state.tool != nil, handle(at: local) == nil, area.rect.contains(local) { return super.hitTest(point) }
        return bounds.contains(local) ? self : nil
    }

    /// What the pointer shows over `point`: a resize arrow on a grip, a hand where dragging moves the area, a
    /// crosshair where a tool draws, an arrow elsewhere (the dimmed screen, the toolbar).
    private func cursor(at point: CGPoint) -> NSCursor {
        if toolbarHolder.frame.contains(point) { return .arrow }
        switch handle(at: point) {
        case let .grip(grip): return grip.cursor
        case .move: return .openHand
        case nil: return state.tool != nil && area.rect.contains(point) ? .crosshair : .arrow
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard drag == nil else { return }
        cursor(at: convert(event.locationInWindow, from: nil)).set()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let handle = handle(at: point) else { return }
        drag = (handle, point, area.rect)
        // Held while dragging: a closed hand moving it, the grip's arrow resizing it.
        if case .move = handle { NSCursor.closedHand.set() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let delta = CGSize(width: point.x - drag.start.x, height: point.y - drag.start.y)
        sizeLabel.isHidden = false
        switch drag.handle {
        case .move: area.rect = moved(drag.rect, by: delta, in: bounds)
        case let .grip(grip): area.rect = grip.resize(drag.rect, by: delta, in: bounds)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        drag = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sizeLabel.isHidden = true
        CATransaction.commit()
        mouseMoved(with: event)
    }
}
