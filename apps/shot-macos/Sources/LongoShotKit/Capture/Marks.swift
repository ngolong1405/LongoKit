import CoreGraphics
import Foundation

/// Something drawn on a capture: an arrow, a pen stroke, a box or a highlight. Points are in the image's pixels,
/// from its top-left, so the same marks draw on screen (scaled) and into the saved picture (as they are).
struct Mark: Identifiable {
    enum Tool: String, CaseIterable, Identifiable {
        case arrow, pen, rectangle, highlighter

        var id: String { rawValue }
    }

    let id = UUID()
    var tool: Tool
    var points: [CGPoint]
    var color: CGColor
    /// Line width in pixels.
    var width: CGFloat

    /// Long enough to keep: a click without a drag draws nothing.
    var isVisible: Bool {
        guard let first = points.first, let last = points.last else { return false }
        if tool == .pen || tool == .highlighter { return points.count > 1 }
        return hypot(last.x - first.x, last.y - first.y) > width
    }

    /// Draws into a context whose coordinates are the image's pixels from the top-left.
    func draw(in context: CGContext) {
        guard let first = points.first, let last = points.last else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(color)
        context.setFillColor(color)
        // A tight shadow keeps marks readable on light and dark captures alike without softening their edges.
        if tool != .highlighter {
            context.setShadow(offset: CGSize(width: 0, height: max(width * 0.15, 1)), blur: width * 0.35,
                              color: CGColor(gray: 0, alpha: 0.4))
        }
        switch tool {
        case .arrow:
            drawArrow(from: first, to: last, in: context)
        case .rectangle:
            let rect = CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(last.x - first.x), height: abs(last.y - first.y))
            // Square corners.
            context.setLineJoin(.miter)
            context.setLineWidth(width)
            context.stroke(rect)
        case .pen:
            context.setLineWidth(width)
            context.addPath(smoothPath())
            context.strokePath()
        case .highlighter:
            context.setBlendMode(.multiply)
            context.setLineCap(.butt)
            context.setStrokeColor(color.copy(alpha: 0.4) ?? color)
            context.setLineWidth(width * 3.5)
            context.addPath(smoothPath())
            context.strokePath()
        }
    }

    /// One solid shape: a shaft that widens from a fine tail to the head, and a sharp head with its barbs swept
    /// back past the neck. Everything grows with the line width.
    private func drawArrow(from start: CGPoint, to end: CGPoint, in context: CGContext) {
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return }
        // Along the arrow, and across it.
        let along = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)
        let across = CGPoint(x: -along.y, y: along.x)
        func point(back: CGFloat, side: CGFloat) -> CGPoint {
            CGPoint(x: end.x - along.x * back + across.x * side, y: end.y - along.y * back + across.y * side)
        }
        let head = min(max(width * 6, 24), length * 0.55)
        let barb = head * 0.48
        let neck = head * 0.7
        let shaft = width * 0.75
        let tail = width * 0.25
        let outline: [CGPoint] = [
            point(back: length, side: tail),
            point(back: neck, side: shaft),
            point(back: head, side: barb),
            end,
            point(back: head, side: -barb),
            point(back: neck, side: -shaft),
            point(back: length, side: -tail),
        ]
        context.setLineJoin(.miter)
        context.addLines(between: outline)
        context.closePath()
        context.fillPath()
    }

    /// The points joined with curves through their midpoints, so a hand-drawn line comes out smooth.
    private func smoothPath() -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in 1..<max(points.count, 1) {
            let previous = points[index - 1], point = points[index]
            path.addQuadCurve(to: CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2), control: previous)
        }
        if let last = points.last { path.addLine(to: last) }
        return path
    }

    /// The capture with `marks` drawn on it, at full size. `origin`: where `image` starts in the marks' pixels, for a
    /// part cut from a larger picture (the marks keep their place).
    static func render(_ marks: [Mark], on image: CGImage, origin: CGPoint = .zero) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -origin.x, y: -origin.y)
        for mark in marks { mark.draw(in: context) }
        return context.makeImage()
    }
}
