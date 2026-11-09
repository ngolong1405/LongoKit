import AppKit
import SwiftUI

/// The menu bar icon: the LongoDisplay mark (a display with a sun) as single-color line art. It's a template
/// image, so macOS tints it to match the menu bar.
enum MenuBarIcon {
    @MainActor static let image: NSImage = {
        let renderer = ImageRenderer(content: Glyph().frame(width: 18, height: 18))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "sun.max", accessibilityDescription: nil)!
        image.isTemplate = true
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
                let ink = GraphicsContext.Shading.color(.black)
                // Screen outline, stand and base.
                context.stroke(Path(roundedRect: rect(1.6, 2.4, 14.8, 10), cornerRadius: 2 * s), with: ink, lineWidth: 1.5 * s)
                context.fill(Path(rect(8.3, 12.4, 1.4, 2.2)), with: ink)
                context.fill(Path(roundedRect: rect(5.4, 14.4, 7.2, 1.5), cornerRadius: 0.75 * s), with: ink)
                // Sun with four ray dots.
                context.fill(Path(ellipseIn: rect(7.2, 5.6, 3.6, 3.6)), with: ink)
                for (x, y) in [(9.0, 3.95), (9.0, 10.85), (5.55, 7.4), (12.45, 7.4)] {
                    context.fill(Path(ellipseIn: rect(x - 0.65, y - 0.65, 1.3, 1.3)), with: ink)
                }
            }
        }
    }
}
