import AppKit
import LongoKitUI
import SwiftUI

/// The menu bar icon: the Longo Share mark (two devices, a file arcing from one to the other), white lines with an
/// amber file. Not a template, so it reads the same on light and dark bars.
enum MenuBarIcon {
    @MainActor static let image: NSImage = {
        let renderer = ImageRenderer(content: Glyph().frame(width: 18, height: 18))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: nil)!
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
                let dark = Color(hex: 0x24303B)
                // Two devices, dark inside with a white outline.
                for x in [1.4, 11.0] {
                    let device = Path(roundedRect: rect(x, 7.6, 5.6, 8.6), cornerRadius: 1.4 * s)
                    context.fill(device, with: .color(dark))
                    context.stroke(device, with: ink, lineWidth: 1.4 * s)
                }
                // The arc from one to the other, with its arrowhead.
                var arc = Path()
                arc.move(to: CGPoint(x: 4.2 * s, y: 6.2 * s))
                arc.addQuadCurve(to: CGPoint(x: 13.8 * s, y: 6.2 * s), control: CGPoint(x: 9 * s, y: -0.6 * s))
                var head = Path()
                head.move(to: CGPoint(x: 11.6 * s, y: 5.6 * s))
                head.addLine(to: CGPoint(x: 13.8 * s, y: 6.2 * s))
                head.addLine(to: CGPoint(x: 14.0 * s, y: 3.9 * s))
                let line = StrokeStyle(lineWidth: 1.4 * s, lineCap: .round, lineJoin: .round)
                context.stroke(arc, with: .color(dark), style: StrokeStyle(lineWidth: 2.6 * s, lineCap: .round))
                context.stroke(arc, with: ink, style: line)
                context.stroke(head, with: ink, style: line)
                // The file on its way.
                context.fill(Path(ellipseIn: rect(7.4, 1.4, 3.2, 3.2)), with: .color(Theme.solar))
            }
        }
    }
}
