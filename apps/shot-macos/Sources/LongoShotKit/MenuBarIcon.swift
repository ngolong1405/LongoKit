import AppKit
import LongoKitUI
import SwiftUI

/// The menu bar icon: the Longo Shot mark (viewfinder corners around a lens), white lines with a dark edge and a
/// Solar Amber center, like the other LongoKit icons. Not a template, so it reads the same on light and dark bars.
enum MenuBarIcon {
    @MainActor static let image = render(center: Theme.solar)
    /// While recording: the lens turns red.
    @MainActor static let recording = render(center: Color(hex: 0xEF4444))
    /// Paused: amber.
    @MainActor static let paused = render(center: Color(hex: 0xF59E0B))

    /// The red icon with the time next to it, as one image. A label made of an image and a changing text makes the
    /// status item re-layout every second, which AppKit can take for a layout loop.
    @MainActor static func recording(seconds: Int, paused isPaused: Bool = false) -> NSImage {
        let text = RecordingBar.time(seconds) as NSString
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(red: 0.23, green: 0.16, blue: 0.14, alpha: 0.9)
        shadow.shadowBlurRadius = 1.5
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white, .shadow: shadow,
        ]
        let textSize = text.size(withAttributes: attributes)
        let icon = isPaused ? paused : recording
        let size = CGSize(width: icon.size.width + 4 + ceil(textSize.width) + 1, height: max(icon.size.height, ceil(textSize.height)))
        let image = NSImage(size: size, flipped: false) { rect in
            icon.draw(in: CGRect(x: 0, y: (rect.height - icon.size.height) / 2, width: icon.size.width, height: icon.size.height))
            text.draw(at: CGPoint(x: icon.size.width + 4, y: (rect.height - textSize.height) / 2), withAttributes: attributes)
            return true
        }
        image.isTemplate = false
        return image
    }

    @MainActor private static func render(center: Color) -> NSImage {
        let renderer = ImageRenderer(content: Glyph(center: center).frame(width: 18, height: 18))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)!
        image.isTemplate = false
        return image
    }

    /// Drawn on an 18-point grid.
    private struct Glyph: View {
        let center: Color

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
                context.fill(Path(ellipseIn: CGRect(x: 7.4 * s, y: 7.4 * s, width: 3.2 * s, height: 3.2 * s)), with: .color(center))
            }
        }
    }
}
