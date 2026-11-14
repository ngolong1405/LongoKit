import AppKit
import LongoKitUI
import SwiftUI

/// The menu bar icon: two screens side by side and the pointer going across. White lines, the pointer in amber.
/// Not a template, so it reads the same on light and dark bars.
enum MenuBarIcon {
    @MainActor static let image: NSImage = {
        let renderer = ImageRenderer(content: Glyph().frame(width: 18, height: 18))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: nil)!
        image.isTemplate = false
        return image
    }()

    @MainActor static let paused = MenuBarPaused.image(from: image)

    private struct Glyph: View {
        var body: some View {
            Canvas { context, size in
                let s = size.width / 18
                func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                    CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
                }
                let ink = GraphicsContext.Shading.color(.white)
                let dark = Color(hex: 0x24303B)
                for x in [0.8, 9.8] {
                    let screen = Path(roundedRect: rect(x, 4, 7.4, 6.4), cornerRadius: 1.4 * s)
                    let base = Path(roundedRect: rect(x - 0.6, 11.4, 8.6, 1.4), cornerRadius: 0.7 * s)
                    // A dark edge under the white, so it shows on a light menu bar too.
                    context.stroke(screen, with: .color(dark), lineWidth: 2.4 * s)
                    context.stroke(base, with: .color(dark), lineWidth: 1 * s)
                    context.fill(screen, with: .color(dark))
                    context.stroke(screen, with: ink, lineWidth: 1.3 * s)
                    context.fill(base, with: ink)
                }
                // The pointer, crossing from one to the other.
                let points: [(CGFloat, CGFloat)] = [(8.3, 5.4), (8.3, 11.4), (9.7, 10.1), (10.8, 12.4), (11.8, 12), (10.7, 9.7), (12.6, 9.6)]
                var arrow = Path()
                arrow.move(to: CGPoint(x: points[0].0 * s, y: points[0].1 * s))
                for point in points.dropFirst() { arrow.addLine(to: CGPoint(x: point.0 * s, y: point.1 * s)) }
                arrow.closeSubpath()
                context.stroke(arrow, with: .color(dark), style: StrokeStyle(lineWidth: 1.6 * s, lineJoin: .round))
                context.fill(arrow, with: .color(Theme.solar))
            }
        }
    }
}
