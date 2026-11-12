import AppKit
import LongoKitUI
import SwiftUI

/// Drawing on an area right after it's captured, where it was on screen: the picture stays in place over a dimmed
/// screen with the drawing toolbar under it. Done hands back the picture with its marks to save and copy as set; ⌘C,
/// to save and copy whatever the clipboard setting; Esc, to copy only; ✕, nothing. With the whole screen at hand (an
/// area or the screen), the area can still be resized from its eight grips and moved by its edges while drawing.
@MainActor
final class InPlaceEditor {
    enum Outcome {
        case save(CGImage)
        case saveAndCopy(CGImage)
        case copy(CGImage)
        case discard
    }

    private static var current: InPlaceEditor?

    /// Captures wait until the open editor is done.
    static var isOpen: Bool { current != nil }

    /// The editor's frame on screen, for the drawing test.
    static var frame: CGRect? { current?.panel?.frame }

    /// The area being drawn on, in points from the screen's top-left, when it can be adjusted.
    static var area: CGRect? { current?.adjustable?.rect }

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
            backdrop.orderFrontRegardless()
            backdrops.append(backdrop)
        }

        let toolbarSize = NSHostingView(rootView: DrawToolbar(state: state) { _ in }).fittingSize
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
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    private func showAdjustable(on screen: NSScreen, area rect: CGRect) {
        // The other screens dim; this one is the editor itself, the area clear and the rest dimmed.
        for other in NSScreen.screens where other != screen {
            let backdrop = Self.panel(other.frame, level: .screenSaver)
            backdrop.contentView = Backdrop(frame: CGRect(origin: .zero, size: other.frame.size), clear: nil)
            backdrop.orderFrontRegardless()
            backdrops.append(backdrop)
        }
        let area = Area(rect)
        adjustable = area
        let toolbarSize = NSHostingView(rootView: DrawToolbar(state: state) { _ in }).fittingSize
        let root = AdjustableEditor(image: image, size: screen.frame.size, state: state, area: area,
                                    toolbar: { Self.layout(area: $0, toolbar: toolbarSize, screen: screen).toolbar }) { [weak self] result in
            self?.finish(result)
        }
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: screen.frame.size)
        let panel = Self.panel(screen.frame, level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1))
        panel.contentView = host
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
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
        switch result {
        case let .done(marks):
            close(with: .save(picture(with: marks)))
        case let .copy(marks):
            close(with: .saveAndCopy(picture(with: marks)))
        case let .clipboard(marks):
            close(with: .copy(picture(with: marks)))
        case .cancel:
            close(with: .discard)
        }
    }

    private func picture(with marks: [Mark]) -> CGImage {
        let drawn = marks.isEmpty ? image : Mark.render(marks, on: image) ?? image
        // The whole screen was at hand: cut the area as it ended up.
        guard let adjustable else { return drawn }
        return Capturer.cut(drawn, scale: state.pixelsPerPoint, to: adjustable.rect) ?? drawn
    }

    private func close(with outcome: Outcome) {
        panel?.orderOut(nil)
        for backdrop in backdrops { backdrop.orderOut(nil) }
        panel = nil
        backdrops = []
        if Self.current === self { Self.current = nil }
        NSCursor.arrow.set()
        completion(outcome)
    }

    private static func panel(_ frame: CGRect, level: NSWindow.Level) -> NSPanel {
        let panel = KeyPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.identifier = Capturer.panelID
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
            NSColor.black.withAlphaComponent(0.45).setFill()
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

/// The whole screen to draw on, the area clear and the rest dimmed, with the area's eight grips and the toolbar.
private struct AdjustableEditor: View {
    let image: CGImage
    let size: CGSize
    @ObservedObject var state: AnnotationState
    @ObservedObject var area: InPlaceEditor.Area
    let toolbar: (CGRect) -> CGRect
    let finish: (Annotator.Result) -> Void
    /// The area when a grip or an edge started being dragged.
    @State private var dragStart: CGRect?

    private var bounds: CGRect { CGRect(origin: .zero, size: size) }

    var body: some View {
        let rect = area.rect
        let bar = toolbar(rect)
        ZStack(alignment: .topLeading) {
            MarkCanvas(image: image, state: state)
                .frame(width: size.width, height: size.height)
            // Outside the area: dimmed, not part of the picture, and nothing draws there.
            Outside(area: rect)
                .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                .contentShape(Outside(area: rect), eoFill: true)
                .onTapGesture {}
            Rectangle()
                .strokeBorder(Theme.solar, lineWidth: 1.5)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
            // The edges move the area.
            ForEach(0..<4, id: \.self) { side in
                edge(side, of: rect)
            }
            ForEach(Grip.allCases, id: \.self) { grip in
                grab(grip, at: grip.point(in: rect))
            }
            if dragStart != nil {
                Text("\(Int(rect.width)) × \(Int(rect.height))")
                    .font(.mono(11, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.72)))
                    .offset(x: rect.minX, y: max(rect.minY - 26, 4))
                    .allowsHitTesting(false)
            }
            DrawToolbar(state: state, finish: finish)
                .fixedSize()
                .offset(x: bar.minX, y: bar.minY)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// A grip: a small white square, a larger target around it.
    private func grab(_ grip: Grip, at point: CGPoint) -> some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous).strokeBorder(Theme.solar, lineWidth: 1.5))
            .frame(width: 10, height: 10)
            .shadow(color: .black.opacity(0.35), radius: 2)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .position(point)
            .onHover { inside in (inside ? NSCursor.crosshair : NSCursor.arrow).set() }
            .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                let start = dragStart ?? area.rect
                dragStart = start
                area.rect = grip.resize(start, by: value.translation, in: bounds)
            }.onEnded { _ in dragStart = nil })
    }

    /// One edge, a thin strip along it: dragging it moves the whole area.
    private func edge(_ side: Int, of rect: CGRect) -> some View {
        let thickness: CGFloat = 10
        let horizontal = side % 2 == 0
        let frame = horizontal
            ? CGRect(x: rect.minX, y: (side == 0 ? rect.minY : rect.maxY) - thickness / 2, width: rect.width, height: thickness)
            : CGRect(x: (side == 1 ? rect.maxX : rect.minX) - thickness / 2, y: rect.minY, width: thickness, height: rect.height)
        return Color.clear
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
            .position(x: frame.midX, y: frame.midY)
            .onHover { inside in (inside ? NSCursor.openHand : NSCursor.arrow).set() }
            .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                let start = dragStart ?? area.rect
                dragStart = start
                area.rect = moved(start, by: value.translation, in: bounds)
            }.onEnded { _ in dragStart = nil })
    }
}

/// Everything but the area.
private struct Outside: Shape {
    let area: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRect(area)
        return path
    }
}
