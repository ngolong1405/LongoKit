import AppKit
import ImageIO
import LongoKitUI
import SwiftUI

/// A window to draw on a capture: arrows, pen strokes, boxes and highlights, in a few colors and sizes. Done saves
/// over the capture's file and copies it; closing without Done leaves the capture as it was.
@MainActor
enum Annotator {
    /// Open editors, kept until they close.
    private static var windows: [NSWindow] = []

    static func open(png: Data, file: URL?, model: AppModel) {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        // Pixels per point, from the PNG's density (144 dpi for a Retina capture).
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let scale = max(((properties?[kCGImagePropertyDPIWidth] as? Double) ?? 72) / 72, 1)

        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        let state = AnnotationState(pixelsPerPoint: scale)
        let view = AnnotatorView(image: image, state: state) { [weak window] result in
            finish(result, image: image, scale: scale, file: file, model: model)
            // Copy leaves the window open to keep drawing.
            if case .copy = result { return }
            window?.close()
        }
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        window.contentViewController = host
        window.title = L("Draw on Capture")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)

        // The picture at its on-screen size, within most of the screen, with room for the toolbar.
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let picture = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let fit = min(1, (visible.width * 0.85) / picture.width, (visible.height * 0.85 - 92) / picture.height)
        let size = CGSize(width: max(picture.width * fit + 32, 760), height: max(picture.height * fit + 92 + 32, 460))
        window.setContentSize(size)
        window.contentMinSize = CGSize(width: 760, height: 420)
        window.center()

        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { note in
            MainActor.assumeIsolated { windows.removeAll { $0 === note.object as? NSWindow } }
        }
        windows.append(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// `clipboard` is Esc right after a capture: copied, never saved.
    enum Result { case done([Mark]), copy([Mark]), clipboard([Mark]), cancel }

    private static func finish(_ result: Result, image: CGImage, scale: CGFloat, file: URL?, model: AppModel) {
        switch result {
        case .cancel:
            return
        case let .copy(marks), let .clipboard(marks):
            guard let drawn = Mark.render(marks, on: image), let png = Output.png(drawn, scale: scale) else { return }
            Output.copy(png: png, file: nil)
        case let .done(marks):
            // Done without drawing anything leaves the capture as it is.
            guard !marks.isEmpty, let drawn = Mark.render(marks, on: image), let png = Output.png(drawn, scale: scale) else { return }
            model.annotated(png, file: file)
        }
    }
}

/// The marks, the one being drawn, and the chosen tool, color and size.
@MainActor
final class AnnotationState: ObservableObject {
    @Published var marks: [Mark] = []
    @Published var undone: [Mark] = []
    @Published var drawing: Mark?
    @Published var tool: Mark.Tool = .arrow
    @Published var color = AnnotationState.palette[0]
    @Published var size = 1
    let pixelsPerPoint: CGFloat

    init(pixelsPerPoint: CGFloat) {
        self.pixelsPerPoint = pixelsPerPoint
    }

    static let palette: [Color] = [
        Color(hex: 0xEF4444), Color(hex: 0xFF6B35), Color(hex: 0xFACC15), Color(hex: 0x22C55E),
        Color(hex: 0x3B82F6), Color(hex: 0x8B5CF6), .white, .black,
    ]
    /// Line widths in points: thin, medium, thick.
    static let sizes: [CGFloat] = [2.5, 5, 9]

    var lineWidth: CGFloat { Self.sizes[size] * pixelsPerPoint }

    func begin(at point: CGPoint) {
        drawing = Mark(tool: tool, points: [point], color: NSColor(color).cgColor, width: lineWidth)
    }

    func extend(to point: CGPoint) {
        guard var mark = drawing else { return }
        if mark.tool == .pen || mark.tool == .highlighter {
            mark.points.append(point)
        } else {
            mark.points = [mark.points[0], point]
        }
        drawing = mark
    }

    func end() {
        if let mark = drawing, mark.isVisible {
            marks.append(mark)
            undone.removeAll()
        }
        drawing = nil
    }

    func undo() {
        guard let last = marks.popLast() else { return }
        undone.append(last)
    }

    func redo() {
        guard let mark = undone.popLast() else { return }
        marks.append(mark)
    }
}

struct AnnotatorView: View {
    let image: CGImage
    @ObservedObject var state: AnnotationState
    let finish: (Annotator.Result) -> Void

    var body: some View {
        VStack(spacing: 0) {
            DrawToolbar(state: state, windowed: true, finish: finish)
            GeometryReader { geometry in
                let fit = fitted(in: geometry.size)
                MarkCanvas(image: image, state: state)
                    .frame(width: fit.width, height: fit.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .padding(16)
        }
        .background(Color(hex: 0x111216))
        .environment(\.colorScheme, .dark)
    }

    /// The picture's size fitted into the space, never larger than its on-screen size.
    private func fitted(in space: CGSize) -> CGSize {
        let width = CGFloat(image.width) / state.pixelsPerPoint, height = CGFloat(image.height) / state.pixelsPerPoint
        let factor = min(1, space.width / width, space.height / height)
        return CGSize(width: width * factor, height: height * factor)
    }
}

/// The capture with its marks, drawn on by dragging. It fills whatever frame it's given.
struct MarkCanvas: View {
    let image: CGImage
    @ObservedObject var state: AnnotationState

    var body: some View {
        GeometryReader { geometry in
            let factor = CGFloat(image.width) / max(geometry.size.width, 1)
            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                Canvas { context, size in
                    let scale = size.width / CGFloat(image.width)
                    context.withCGContext { cg in
                        cg.scaleBy(x: scale, y: scale)
                        for mark in state.marks { mark.draw(in: cg) }
                        state.drawing?.draw(in: cg)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    if state.drawing == nil {
                        state.begin(at: CGPoint(x: value.startLocation.x * factor, y: value.startLocation.y * factor))
                    }
                    state.extend(to: CGPoint(x: value.location.x * factor, y: value.location.y * factor))
                }
                .onEnded { _ in state.end() })
            .onHover { inside in (inside ? NSCursor.crosshair : NSCursor.arrow).set() }
        }
    }
}

/// Tools, colors, sizes, undo and redo, and Cancel / Done. `windowed` is the drawing window's full-width bar (with
/// Copy); otherwise it's the floating bar under a capture being drawn on in place.
struct DrawToolbar: View {
    @ObservedObject var state: AnnotationState
    var windowed = false
    let finish: (Annotator.Result) -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                tool(.arrow, symbol: "line.diagonal.arrow", title: L("Arrow"), key: "a")
                tool(.pen, symbol: "scribble", title: L("Pen"), key: "p")
                tool(.rectangle, symbol: "rectangle", title: L("Box"), key: "r")
                tool(.highlighter, symbol: "highlighter", title: L("Highlighter"), key: "h")
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
            divider
            HStack(spacing: 6) {
                ForEach(Array(AnnotationState.palette.enumerated()), id: \.offset) { _, color in
                    let selected = state.color == color
                    Button { state.color = color } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.25)))
                            .padding(3)
                            .overlay(Circle().strokeBorder(selected ? Color.white : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            divider
            HStack(spacing: 2) {
                ForEach(0..<AnnotationState.sizes.count, id: \.self) { index in
                    let selected = state.size == index
                    Button { state.size = index } label: {
                        Circle()
                            .fill(selected ? Color.white : Color.white.opacity(0.55))
                            .frame(width: 4 + CGFloat(index) * 4, height: 4 + CGFloat(index) * 4)
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? Color.white.opacity(0.14) : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help([L("Thin"), L("Medium"), L("Thick")][index])
                }
            }
            divider
            iconButton("arrow.uturn.backward", help: L("Undo") + " (⌘Z)", disabled: state.marks.isEmpty) { state.undo() }
                .keyboardShortcut("z")
            iconButton("arrow.uturn.forward", help: L("Redo") + " (⇧⌘Z)", disabled: state.undone.isEmpty) { state.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            if windowed {
                Spacer(minLength: 8)
                Button(L("Cancel")) { finish(.cancel) }
                    .buttonStyle(GhostButtonStyle(compact: false))
                    .keyboardShortcut(.cancelAction)
                    .help(L("Close without changes"))
            } else {
                divider
                // Right after a capture nothing is lost by accident: Esc copies (without saving); only ✕ throws it away.
                Button { finish(.cancel) } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Throw this capture away"))
            }
            if windowed {
                Button { finish(.copy(state.marks)) } label: { Label(L("Copy"), systemImage: "doc.on.doc") }
                    .buttonStyle(GhostButtonStyle(compact: false))
                    .keyboardShortcut("c")
                    .help(L("Copy (⌘C)"))
            }
            Button { finish(.done(state.marks)) } label: { Label(L("Done"), systemImage: "checkmark") }
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .help(windowed ? L("Save over the capture and copy it") : L("Save and copy the capture (↩ or ⌘C); Esc only copies"))
                // Right after a capture the capture is copied anyway, so there's no Copy button: ⌘C saves and copies
                // like Done, Esc only copies (hidden buttons taking no room).
                .background {
                    if !windowed {
                        Button("") { finish(.copy(state.marks)) }.keyboardShortcut("c").opacity(0).accessibilityHidden(true)
                        Button("") { finish(.clipboard(state.marks)) }.keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true)
                    }
                }
        }
        .modifier(Chrome(windowed: windowed))
    }

    private struct Chrome: ViewModifier {
        let windowed: Bool

        func body(content: Content) -> some View {
            if windowed {
                content
                    .padding(.leading, 84)
                    .padding(.trailing, 14)
                    .frame(height: 60)
                    .background(Color(hex: 0x17181D))
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
            } else {
                content
                    .padding(.horizontal, 10)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0x111216).opacity(0.96)))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
                    .environment(\.colorScheme, .dark)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 24)
    }

    private func tool(_ tool: Mark.Tool, symbol: String, title: String, key: KeyEquivalent) -> some View {
        let selected = state.tool == tool
        return Button { state.tool = tool } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.6))
                .frame(width: 34, height: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? Theme.solar : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: [])
        .help("\(title) (\(String(key.character).uppercased()))")
    }

    private func iconButton(_ symbol: String, help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(disabled ? 0.3 : 0.85))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }
}
