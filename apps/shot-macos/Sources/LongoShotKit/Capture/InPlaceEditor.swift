import AppKit
import LongoKitUI
import SwiftUI

/// Drawing on an area right after it's captured, where it was on screen: the picture stays in place over a dimmed
/// screen with the drawing toolbar under it. Done hands back the picture with its marks to save and copy as set; ⌘C,
/// to save and copy whatever the clipboard setting; Esc, to copy only; ✕, nothing.
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

    static func cancel() { current?.close(with: .discard) }

    private let image: CGImage
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
        marks.isEmpty ? image : Mark.render(marks, on: image) ?? image
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
