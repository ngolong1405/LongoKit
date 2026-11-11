import AppKit
import LongoKitUI
import SwiftUI
import UniformTypeIdentifiers

/// The small card in the screen's corner after a capture: the picture to drag into another app, Copy and Show in
/// Finder; or a short message (text copied, nothing found). It goes away on its own unless the pointer is on it.
@MainActor
final class PreviewPanel {
    static let shared = PreviewPanel()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private var lifetime: TimeInterval = 6

    struct Capture {
        let thumbnail: NSImage
        let png: Data
        let file: URL?
    }

    func show(_ capture: Capture, on screen: NSScreen?) {
        lifetime = 6
        present(CaptureCard(capture: capture, panel: self), on: screen)
    }

    func message(_ title: String, detail: String? = nil, symbol: String, tint: Color, on screen: NSScreen?) {
        lifetime = 2.5
        present(MessageCard(title: title, detail: detail, symbol: symbol, tint: tint), on: screen)
    }

    func dismiss() {
        hideWork?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }

    fileprivate func hovering(_ inside: Bool) {
        if inside { hideWork?.cancel() } else { scheduleHide() }
    }

    private func present<V: View>(_ content: V, on screen: NSScreen?) {
        dismiss()
        let host = NSHostingView(rootView: content.padding(14))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let visible = (screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let frame = CGRect(x: visible.maxX - size.width - 6, y: visible.minY + 6, width: size.width, height: size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        self.panel = panel
        scheduleHide()
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.panel else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    if self?.panel === panel { self?.dismiss() }
                }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime, execute: work)
    }

    /// A small copy of the capture for the card, so the full picture isn't kept around.
    static func thumbnail(_ image: CGImage, maxPixels: Int = 520) -> NSImage {
        let factor = min(1, CGFloat(maxPixels) / CGFloat(max(image.width, image.height)))
        let width = max(1, Int(CGFloat(image.width) * factor)), height = max(1, Int(CGFloat(image.height) * factor))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return NSImage(cgImage: image, size: .zero)
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = context.makeImage() else { return NSImage(cgImage: image, size: .zero) }
        return NSImage(cgImage: small, size: CGSize(width: width / 2, height: height / 2))
    }
}

private struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .background(ZStack { VisualEffectBackground(); Theme.island.opacity(0.6) }.clipShape(shape))
            .overlay(shape.strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

private struct CaptureCard: View {
    let capture: PreviewPanel.Capture
    let panel: PreviewPanel
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: capture.thumbnail)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 232, maxHeight: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))
                .onDrag { dragItem }
                .onTapGesture { if let file = capture.file { NSWorkspace.shared.open(file); panel.dismiss() } }
                .help(capture.file == nil ? L("Drag into another app") : L("Drag into another app, or click to open"))
            HStack(spacing: 6) {
                Button { Output.copy(png: capture.png, file: capture.file); copied = true } label: {
                    Label(copied ? L("Copied") : L("Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(GhostButtonStyle(compact: true))
                if let file = capture.file {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([file]); panel.dismiss() } label: {
                        Label(L("Show in Finder"), systemImage: "folder")
                    }
                    .buttonStyle(GhostButtonStyle(compact: true))
                }
                Spacer(minLength: 0)
                Button { panel.dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textMuted)
                        .frame(width: 22, height: 22).background(Circle().fill(Theme.tint(0.06)))
                }
                .buttonStyle(.plain)
                .help(L("Close"))
            }
        }
        .padding(10)
        .frame(width: 252)
        .modifier(CardBackground())
        .onHover { hovering = $0; panel.hovering($0) }
    }

    private var dragItem: NSItemProvider {
        if let file = capture.file, let provider = NSItemProvider(contentsOf: file) { return provider }
        return NSItemProvider(item: capture.png as NSData, typeIdentifier: UTType.png.identifier)
    }
}

private struct MessageCard: View {
    let title: String
    let detail: String?
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            GlyphTile(tint: tint, size: 32) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                if let detail {
                    Text(detail).font(.ui(11)).foregroundStyle(Theme.textMuted).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 300)
        .modifier(CardBackground())
    }
}
