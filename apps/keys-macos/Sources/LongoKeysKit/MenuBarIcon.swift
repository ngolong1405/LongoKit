import AppKit
import LongoKitUI
import SwiftUI

/// The menu bar icon: a keyboard colored like Longo Mouse's and Longo Display's icons: white keys on a dark body,
/// with the Caps Lock key (the Hyper key) in Solar Amber. Not a template, so it reads on light and dark bars.
enum MenuBarIcon {
    @MainActor static let image: NSImage = {
        let renderer = ImageRenderer(content: Glyph().frame(width: 18, height: 18))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)!
        image.isTemplate = false
        return image
    }()

    /// While paused: faded, with a slash.
    @MainActor static let paused = MenuBarPaused.image(from: image)

    /// Drawn on an 18-point grid.
    private struct Glyph: View {
        var body: some View {
            Canvas { context, size in
                let s = size.width / 18
                func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                    CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
                }
                let ink = GraphicsContext.Shading.color(.white)
                let body = Path(roundedRect: rect(1, 4, 16, 10.5), cornerRadius: 2.2 * s)
                context.fill(body, with: .color(Color(hex: 0x3B2A24)))
                context.stroke(body, with: ink, lineWidth: 1.4 * s)
                // Two rows of keys, the Caps Lock key first on the second row, then the space bar.
                for i in 0..<5 { context.fill(Path(roundedRect: rect(3.2 + CGFloat(i) * 2.4, 6.1, 1.6, 1.4), cornerRadius: 0.4 * s), with: ink) }
                context.fill(Path(roundedRect: rect(3.2, 8.6, 2.6, 1.4), cornerRadius: 0.4 * s), with: .color(Theme.solar))
                for i in 0..<4 { context.fill(Path(roundedRect: rect(6.6 + CGFloat(i) * 2.2, 8.6, 1.5, 1.4), cornerRadius: 0.4 * s), with: ink) }
                context.fill(Path(roundedRect: rect(5.5, 11.1, 7, 1.4), cornerRadius: 0.5 * s), with: ink)
            }
        }
    }
}
