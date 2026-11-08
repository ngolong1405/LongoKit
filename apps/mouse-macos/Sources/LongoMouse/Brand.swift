import SwiftUI

enum Brand {
    static let sun = Color(hex: 0xFACC15)
    static let orchid = Color(hex: 0xE879F9)

    /// The "Solar Sunset Violet" app icon, also used as the in-app logo.
    static var logo: NSImage? { Resource.image("Logo.png") }
    /// The same mark on a white tile, for the light appearance.
    static var lightLogo: NSImage? { Resource.image("LogoLight.png") }

    static func logo(dark: Bool) -> NSImage? { dark ? logo : (lightLogo ?? logo) }

    /// Menu bar status item for the current state. Idle is a template so it follows the menu bar's appearance.
    @MainActor
    static func menuBarImage(_ state: MouseGlyph.State) -> NSImage {
        if let cached = menuBarCache[state] { return cached }
        let renderer = ImageRenderer(content: MouseGlyph(state: state, size: 18))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = state == .idle
        menuBarCache[state] = image
        return image
    }

    @MainActor private static var menuBarCache: [MouseGlyph.State: NSImage] = [:]
}

/// The mouse mark from the menu bar set: outlined body, scroll wheel and two flank buttons, on a 24pt grid.
struct MouseGlyph: View {
    enum State {
        case idle, running, listening
    }

    var state: State = .idle
    var size: CGFloat = 24
    /// Overrides used when the glyph serves as a nav icon or button preview.
    var outline: Color?
    var detail: Color?
    /// CG button number to light up in Solar Amber (2 = wheel, 3 = rear flank, 4 = front flank).
    var highlight: Int?

    var body: some View {
        let colors = palette
        Canvas { context, canvas in
            let s = canvas.width / 24
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
            }
            func line(_ x: CGFloat, _ y1: CGFloat, _ y2: CGFloat) -> Path {
                var path = Path()
                path.move(to: CGPoint(x: x * s, y: y1 * s))
                path.addLine(to: CGPoint(x: x * s, y: y2 * s))
                return path
            }
            func lit(_ button: Int) -> Color { highlight == button ? Theme.solar : colors.detail }

            if state == .listening {
                context.stroke(Path(ellipseIn: rect(0.8, 0.8, 22.4, 22.4)), with: .color(Theme.magenta.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 1 * s, dash: [1.6 * s, 1.4 * s]))
            }
            let body = Path(roundedRect: rect(7.5, 4, 9.5, 15.5), cornerRadius: 4.75 * s)
            if let fill = colors.fill { context.fill(body, with: .color(fill)) }
            context.stroke(body, with: .color(colors.outline), lineWidth: 1.6 * s)
            context.stroke(line(12.25, 4, 6.6), with: .color(colors.outline), lineWidth: 1.2 * s)

            // Glow pass under the highlighted part.
            var glow = context
            glow.addFilter(.shadow(color: Theme.solar.opacity(0.9), radius: 2.5 * s))
            let wheel = Path(roundedRect: rect(11.55, 6.6, 1.4, 3.2), cornerRadius: 0.7 * s)
            (highlight == 2 ? glow : context).fill(wheel, with: .color(lit(2)))
            for (button, y) in [(4, CGFloat(10.5)), (3, CGFloat(13.4))] {
                (highlight == button ? glow : context).stroke(
                    line(5.4, y, y + 2), with: .color(lit(button)),
                    style: StrokeStyle(lineWidth: 1.3 * s, lineCap: .round))
            }
            if state == .running {
                context.fill(Path(ellipseIn: rect(17.2, 1.8, 3.8, 3.8)), with: .color(Theme.solar))
            }
        }
        .frame(width: size, height: size)
    }

    private var palette: (outline: Color, detail: Color, fill: Color?) {
        if let outline { return (outline, detail ?? outline, nil) }
        switch state {
        case .idle: return (.white, Color.white.opacity(0.85), nil)
        case .running: return (.white, Theme.solar, Color(hex: 0x3B2A24))
        case .listening: return (Brand.orchid, Brand.sun, Color(hex: 0x4A1D5C))
        }
    }
}

/// The app icon artwork. Paused states show it desaturated.
struct AppLogo: View {
    var size: CGFloat
    var dimmed = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let logo = Brand.logo(dark: scheme == .dark) {
            Image(nsImage: logo)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .saturation(dimmed ? 0 : 1)
                .opacity(dimmed ? 0.75 : 1)
                .animation(.easeOut(duration: 0.25), value: dimmed)
        }
    }
}
