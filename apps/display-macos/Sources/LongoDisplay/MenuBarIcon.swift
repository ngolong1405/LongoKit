import AppKit
import LongoKitUI
import SwiftUI

/// The menu bar icon: the LongoDisplay mark (a display with a sun), colored like Longo Mouse's: white lines on a
/// dark screen, with the sun's center in Solar Amber. Not a template, so it reads the same on light and dark bars.
enum MenuBarIcon {
    @MainActor static let image: NSImage = {
        let renderer = ImageRenderer(content: Glyph().frame(width: 18, height: 18))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "sun.max", accessibilityDescription: nil)!
        image.isTemplate = false
        return image
    }()

    /// Drawn on an 18-point grid.
    private struct Glyph: View {
        var body: some View {
            Canvas { context, size in
                let s = size.width / 18
                func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                    CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
                }
                let ink = GraphicsContext.Shading.color(.white)
                let dark = Color(hex: 0x3B2A24)
                // Stand and base, with a dark edge so the white shows on a light menu bar too.
                let stand = Path(rect(8.3, 12.4, 1.4, 2.2))
                let base = Path(roundedRect: rect(5.4, 14.4, 7.2, 1.5), cornerRadius: 0.75 * s)
                for part in [stand, base] { context.stroke(part, with: .color(dark), lineWidth: 1 * s) }
                for part in [stand, base] { context.fill(part, with: ink) }
                // Screen: dark inside, white outline.
                let screen = Path(roundedRect: rect(1.6, 2.4, 14.8, 10), cornerRadius: 2 * s)
                context.fill(screen, with: .color(dark))
                context.stroke(screen, with: ink, lineWidth: 1.5 * s)
                // Sun: an amber center with four white ray dots.
                context.fill(Path(ellipseIn: rect(7.2, 5.6, 3.6, 3.6)), with: .color(Theme.solar))
                for (x, y) in [(9.0, 3.95), (9.0, 10.85), (5.55, 7.4), (12.45, 7.4)] {
                    context.fill(Path(ellipseIn: rect(x - 0.65, y - 0.65, 1.3, 1.3)), with: ink)
                }
            }
        }
    }
}
