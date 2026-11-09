import AppKit

/// The menu bar icon while an app is paused: the same mark, faded, with a slash through it, the same in every
/// LongoKit app. White with a dark edge, so it reads on light and dark menu bars.
public enum MenuBarPaused {
    public static func image(from base: NSImage) -> NSImage {
        let size = base.size
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.4)
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: rect.width * 0.17, y: rect.height * 0.17))
            slash.line(to: NSPoint(x: rect.width * 0.83, y: rect.height * 0.83))
            slash.lineCapStyle = .round
            NSColor(red: 0.23, green: 0.16, blue: 0.14, alpha: 1).setStroke()
            slash.lineWidth = rect.width * 0.2
            slash.stroke()
            NSColor.white.setStroke()
            slash.lineWidth = rect.width * 0.09
            slash.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}
