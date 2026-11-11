import AppKit
import LongoKitUI
import SwiftUI

/// The menu bar icon: the Longo Shot mark (viewfinder corners around a lens), white lines with a dark edge and a
/// Solar Amber center, like the other LongoKit icons. Not a template, so it reads the same on light and dark bars.
enum MenuBarIcon {
    @MainActor static let image: NSImage = {
        let renderer = ImageRenderer(content: Glyph().frame(width: 18, height: 18))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)!
        image.isTemplate = false
        return image
    }()

    /// Drawn on an 18-point grid.
    private struct Glyph: View {
        var body: some View {
            Canvas { context, size in
                let s = size.width / 18
                func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
                let dark = Color(hex: 0x3B2A24)
                // Four corners, each an L with a rounded bend.
                var corners = Path()
                for (x, y, dx, dy) in [(2.0, 2.0, 1.0, 1.0), (16.0, 2.0, -1.0, 1.0), (16.0, 16.0, -1.0, -1.0), (2.0, 16.0, 1.0, -1.0)] {
                    corners.move(to: point(x, y + 3.6 * dy))
                    corners.addLine(to: point(x, y + 1.2 * dy))
                    corners.addQuadCurve(to: point(x + 1.2 * dx, y), control: point(x, y))
                    corners.addLine(to: point(x + 3.6 * dx, y))
                }
                let lens = Path(ellipseIn: CGRect(x: 5.6 * s, y: 5.6 * s, width: 6.8 * s, height: 6.8 * s))
                for part in [corners, lens] {
                    context.stroke(part, with: .color(dark), style: StrokeStyle(lineWidth: 2.9 * s, lineCap: .round, lineJoin: .round))
                }
                for part in [corners, lens] {
                    context.stroke(part, with: .color(.white), style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round, lineJoin: .round))
                }
                context.fill(Path(ellipseIn: CGRect(x: 7.4 * s, y: 7.4 * s, width: 3.2 * s, height: 3.2 * s)), with: .color(Theme.solar))
            }
        }
    }
}
