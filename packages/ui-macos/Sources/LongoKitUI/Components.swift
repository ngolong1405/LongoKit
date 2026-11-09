import CoreText
import SwiftUI

// Tokens from the "Solar Sunset & Cyber-Violet" design token system. Every color resolves per
// appearance, so the whole UI follows the Light/Dark setting (or macOS when set to System).

public enum Theme {
    public static let windowWidth: CGFloat = 900
    /// Height of the page area between the tab bar and the footer, the same on every tab.
    public static let contentHeight: CGFloat = 700
    public static let windowRadius: CGFloat = 16

    // Accents
    public static let solar = Color.dynamic(dark: 0xFF6B35, light: 0xEE5A22)
    /// Solar Flame on dark, Solar Deep on light: readable accent text in both.
    public static let solarLight = Color.dynamic(dark: 0xFFA26B, light: 0xD94814)
    public static let violet = Color.dynamic(dark: 0x8B5CF6, light: 0x7C3AED)
    public static let violetLight = Color.dynamic(dark: 0xA78BFA, light: 0x6D28D9)
    /// Secondary highlight (listening, picked tiles); same Cyber-Violet family.
    public static let magenta = violet
    public static let magentaLight = violetLight
    public static let accentGradient = LinearGradient(colors: [solar, violet], startPoint: .topLeading, endPoint: .bottomTrailing)

    // Status
    public static let emerald = Color.dynamic(dark: 0x10B981, light: 0x059669)
    public static let amber = Color.dynamic(dark: 0xF59E0B, light: 0xD97706)
    public static let danger = Color.dynamic(dark: 0xEF4444, light: 0xDC2626)
    public static let info = Color(hex: 0x06B6D4)

    // Surfaces
    public static let canvas = Color.dynamic(dark: 0x0B0C10, light: 0xF5F6F8)
    public static let canvasTop = Color.dynamic(dark: 0x121319, light: 0xFFFFFF)
    public static let pane = Color.dynamic(dark: 0x161820, light: 0xF8F9FA, darkOpacity: 0.72, lightOpacity: 0.9)
    public static let island = Color.dynamic(dark: 0x1A1B22, light: 0xFFFFFF, darkOpacity: 0.85, lightOpacity: 0.94)
    public static let well = Color.dynamic(dark: 0x0C0E13, light: 0xE9EBEF, darkOpacity: 0.8, lightOpacity: 1)
    public static let hover = Color.dynamic(dark: 0x242632, light: 0xEDF0F5)
    public static let slate = Color.dynamic(dark: 0x2F3242, light: 0xE1E5ED)
    /// Footer and other chrome strips.
    public static let chrome = Color.dynamic(dark: 0x000000, light: 0x000000, darkOpacity: 0.25, lightOpacity: 0.03)
    public static let popoverTop = Color.dynamic(dark: 0x1B1A24, light: 0xFFFFFF)
    public static let popoverBottom = Color.dynamic(dark: 0x0B0C10, light: 0xF5F6F8)
    public static let showcaseTop = Color.dynamic(dark: 0x2A1A26, light: 0xFFF1EA)
    public static let showcaseBottom = Color.dynamic(dark: 0x16131D, light: 0xF4EEFF)
    public static let listenTop = Color.dynamic(dark: 0x241A3A, light: 0xF1EAFF)
    public static let listenBottom = Color.dynamic(dark: 0x16121F, light: 0xFBF8FF)
    public static let segmentTrack = Color.dynamic(dark: 0x0C0E13, light: 0xE6E8EC, darkOpacity: 0.8, lightOpacity: 1)
    public static let segmentSelected = Color.dynamic(dark: 0x2F3242, light: 0xFFFFFF)
    /// Soft card elevation (`--shadow-card`).
    public static let cardShadow = Color.dynamic(dark: 0x000000, light: 0x000000, darkOpacity: 0.35, lightOpacity: 0.07)
    public static let innerShadow = Color.dynamic(dark: 0x000000, light: 0x000000, darkOpacity: 0.6, lightOpacity: 0.12)

    // Borders
    public static let hairline = Color.dynamic(dark: 0xFFFFFF, light: 0x000000, darkOpacity: 0.08, lightOpacity: 0.08)
    public static let borderProminent = Color.dynamic(dark: 0xFFFFFF, light: 0x000000, darkOpacity: 0.16, lightOpacity: 0.14)
    public static let rim = LinearGradient(
        colors: [Color.dynamic(dark: 0xFFFFFF, light: 0x000000, darkOpacity: 0.14, lightOpacity: 0.1),
                 Color.dynamic(dark: 0xFFFFFF, light: 0x000000, darkOpacity: 0.04, lightOpacity: 0.06)],
        startPoint: .top, endPoint: .bottom)
    public static let cardRim = LinearGradient(colors: [solar.opacity(0.3), violet.opacity(0.3)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)

    // Text
    public static let text = Color.dynamic(dark: 0xF3F4F6, light: 0x111827)
    public static let textSecondary = Color.dynamic(dark: 0xD1D5DB, light: 0x374151)
    public static let textMuted = Color.dynamic(dark: 0x9CA3AF, light: 0x4B5563)
    public static let textFaint = Color.dynamic(dark: 0x6B7280, light: 0x9CA3AF)

    /// Neutral overlay that reads on both themes: white on dark, black on light.
    public static func tint(_ opacity: Double) -> Color {
        Color.dynamic(dark: 0xFFFFFF, light: 0x000000, darkOpacity: opacity, lightOpacity: opacity * 0.7)
    }
}

/// Shared animation curves so every transition in the app feels the same.
public enum Motion {
    /// Selection pills sliding between options.
    public static let slide = Animation.spring(response: 0.3, dampingFraction: 0.86)
    /// Rows appearing, disappearing or reordering.
    public static let list = Animation.spring(response: 0.34, dampingFraction: 0.88)
    /// Small state swaps such as hover or edit mode.
    public static let quick = Animation.easeOut(duration: 0.15)
    /// Inserted rows fade and drop in; removed rows fade out.
    public static let row = AnyTransition.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)), removal: .opacity)
}

public enum AppAppearance: String, CaseIterable, Codable {
    case system, dark, light

    public var title: String {
        switch self {
        case .system: return L("System")
        case .light: return L("Light")
        case .dark: return L("Dark")
        }
    }

    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// A color that resolves against the view's effective appearance.
    static func dynamic(dark: UInt32, light: UInt32, darkOpacity: Double = 1, lightOpacity: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: isDark ? darkOpacity : lightOpacity)
        })
    }
}

public extension Font {
    /// Space Grotesk: titles, mode switchers.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom("Space Grotesk", size: size).weight(weight)
    }

    /// Geist: body copy and descriptions.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Geist", size: size).weight(weight)
    }

    /// JetBrains Mono: labels, chips, values, modifier tags.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .custom("JetBrains Mono", size: size).weight(weight)
    }
}

public enum Fonts {
    /// Registers the bundled OFL fonts for this process. Missing files fall back to the system font.
    public static func register() {
        for name in ["SpaceGrotesk", "Geist", "JetBrainsMono"] {
            if let url = Resource.url(for: "Fonts/\(name).ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

public extension View {
    /// Level 1: obsidian translucent glass with a top-lit inner boundary.
    func panel(padding: CGFloat = 16, radius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Theme.island).shadow(color: Theme.cardShadow, radius: 8, y: 2))
            .overlay(shape.strokeBorder(Theme.hairline))
    }

    /// Level 2: deep hardware tile framed by a solar→violet micro-border.
    func card(padding: CGFloat = 16, radius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Theme.island).shadow(color: Theme.cardShadow, radius: 8, y: 2))
            .overlay(shape.strokeBorder(Theme.hairline))
    }

    /// Dark glass inset well: track trenches, inputs, dropdowns, segmented controls.
    func recessed(radius: CGFloat = 8) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(shape.fill(Theme.well))
            .overlay(
                shape.stroke(Theme.innerShadow, lineWidth: 2)
                    .blur(radius: 1.5)
                    .offset(y: 1)
                    .mask(shape)
            )
            .overlay(shape.strokeBorder(Theme.tint(0.06)))
    }
}

public struct Hairline: View {
    public var color: Color = Theme.hairline

    public init(color: Color = Theme.hairline) { self.color = color }

    public var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

/// Uppercase JetBrains Mono micro label ("STARTUP & BEHAVIOR").
public struct SectionLabel: View {
    public let text: String

    public init(text: String) { self.text = text }

    public var body: some View {
        Text(text.uppercased())
            .font(.mono(10, .medium))
            .tracking(0.5)
            .foregroundStyle(Theme.textFaint)
    }
}

// MARK: - Resources & icons

public enum Resource {
    private static var imageCache: [String: NSImage] = [:]
    /// The app's `Support` folder, used when running via `swift run` where there's no app bundle.
    public static var developmentSupport: URL?

    /// `Contents/Resources/<path>`, falling back to the app's `Support/<path>` when run via `swift run`.
    public static func url(for path: String) -> URL? {
        if let resources = Bundle.main.resourceURL {
            let url = resources.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        guard let source = developmentSupport?.appendingPathComponent(path) else { return nil }
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }

    public static func image(_ path: String, template: Bool = false) -> NSImage? {
        let key = template ? path + "#template" : path
        if let cached = imageCache[key] { return cached }
        guard let url = url(for: path), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = template
        imageCache[key] = image
        return image
    }
}

/// Rounded tile holding a glyph, tinted with an accent.
public struct GlyphTile<Glyph: View>: View {
    public var tint: Color = Theme.violet
    public var size: CGFloat = 32
    @ViewBuilder public let glyph: Glyph

    public init(tint: Color = Theme.violet, size: CGFloat = 32, @ViewBuilder glyph: () -> Glyph) {
        self.tint = tint
        self.size = size
        self.glyph = glyph()
    }

    public var body: some View {
        glyph
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tint.opacity(0.35)))
    }
}

// MARK: - Controls

/// Sequoia toggle: muted slate when off, bursting into Solar Amber with an ambient glow when on.
public struct DSSwitch: View {
    public let isOn: Bool
    public let action: () -> Void

    public init(isOn: Bool, action: @escaping () -> Void) {
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(isOn ? AnyShapeStyle(LinearGradient(colors: [Theme.solar, Color(hex: 0xFF8A50)],
                                                          startPoint: .leading, endPoint: .trailing))
                           : AnyShapeStyle(Theme.slate))
                .overlay(
                    Capsule().stroke(Theme.innerShadow, lineWidth: 2).blur(radius: 1.5).offset(y: 1).mask(Capsule())
                )
                .overlay(Capsule().strokeBorder(Theme.tint(isOn ? 0.2 : 0.06)))
                .shadow(color: Theme.solar.opacity(isOn ? 0.45 : 0), radius: 8)
            Circle()
                .fill(Color.white)
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                .offset(x: isOn ? 20 : 2)
        }
        .frame(width: 40, height: 22)
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isOn)
    }
}

public extension DSSwitch {
    init(isOn: Binding<Bool>) {
        self.init(isOn: isOn.wrappedValue) { isOn.wrappedValue.toggle() }
    }
}

public struct DSCheckbox: View {
    public let isOn: Bool
    public let action: () -> Void

    public init(isOn: Bool, action: @escaping () -> Void) {
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        ZStack {
            if isOn {
                shape.fill(Theme.solar)
                    .overlay(shape.fill(LinearGradient(colors: [Theme.tint(0.25), .clear], startPoint: .top, endPoint: .bottom)))
                    .shadow(color: Theme.solar.opacity(0.45), radius: 5)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
            } else {
                Color.clear.recessed(radius: 4)
            }
        }
        .frame(width: 16, height: 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

/// Precision track: obsidian trench, glowing solar fill, sculpted metal thumb with an amber aperture.
public struct DSSlider: View {
    @Binding public var value: Double
    public let range: ClosedRange<Double>
    public var step: Double = 0.01
    @Environment(\.isEnabled) private var isEnabled
    /// Off for snapshots: ImageRenderer can't draw the AppKit view that catches the wheel.
    public static var scrollWheelAdjusts = true

    /// Where the fill starts. With an origin inside the range (0 on a -80…100 slider), the fill runs from it to
    /// the knob: Solar above, violet below, with a tick at the origin.
    public var origin: Double?

    public init(value: Binding<Double>, range: ClosedRange<Double>, step: Double = 0.01, origin: Double? = nil) {
        self._value = value
        self.range = range
        self.step = step
        self.origin = origin
    }

    public var body: some View {
        GeometryReader { geometry in
            let travel = geometry.size.width - 18
            let span = range.upperBound - range.lowerBound
            let fraction = (value - range.lowerBound) / span
            ZStack(alignment: .leading) {
                Color.clear.frame(height: 6).recessed(radius: 3)
                if let origin, origin > range.lowerBound {
                    let start = (origin - range.lowerBound) / span
                    let below = value < origin
                    // The stretch below the origin, faintly violet so it reads as a different zone.
                    Capsule()
                        .fill(Theme.violet.opacity(0.18))
                        .frame(width: travel * start + 9, height: 6)
                    Capsule()
                        .fill(below ? AnyShapeStyle(LinearGradient(colors: [Theme.violet, Theme.violetLight], startPoint: .leading, endPoint: .trailing))
                                    : AnyShapeStyle(Theme.accentGradient))
                        .frame(width: max(travel * abs(fraction - start), 0), height: 6)
                        .offset(x: travel * min(fraction, start) + 9)
                        .shadow(color: (below ? Theme.violet : Theme.solar).opacity(0.5), radius: 5)
                    Capsule()
                        .fill(Theme.tint(0.45))
                        .frame(width: 2, height: 12)
                        .offset(x: travel * start + 8)
                } else {
                    Capsule()
                        .fill(Theme.accentGradient)
                        .frame(width: max(travel * fraction + 9, 6), height: 6)
                        .shadow(color: Theme.solar.opacity(0.5), radius: 5)
                }
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(hex: 0xF4F4F6), Color(hex: 0xA9ABB3)],
                                                 startPoint: .top, endPoint: .bottom))
                    Circle().strokeBorder(Theme.tint(0.6), lineWidth: 0.5)
                    Circle().fill(Theme.solar).frame(width: 6, height: 6).shadow(color: Theme.solar, radius: 3)
                }
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                .offset(x: travel * fraction)
            }
            .frame(height: 18)
            // Grabbable a little above and below the track too, without taking more room.
            .contentShape(Rectangle().inset(by: -6))
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let f = min(max((drag.location.x - 9) / travel, 0), 1)
                let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
                value = (raw / step).rounded() * step
            })
        }
        .frame(height: 18)
        // The scroll wheel over the slider moves it: each notch is 2% of the range.
        .background {
            if Self.scrollWheelAdjusts {
                ScrollWheelCatcher(enabled: isEnabled) { notches in
                    let span = range.upperBound - range.lowerBound
                    let raw = min(max(value + notches * span * 0.02, range.lowerBound), range.upperBound)
                    value = (raw / step).rounded() * step
                }
            }
        }
    }
}

/// Hands scroll-wheel movement over a view to `onScroll`, in wheel notches (positive = wheel up / fingers up,
/// whatever the scroll direction setting), and keeps it from scrolling the page underneath. Clicks pass through.
struct ScrollWheelCatcher: NSViewRepresentable {
    var enabled: Bool
    var onScroll: (Double) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = enabled ? onScroll : nil
    }

    final class CatcherView: NSView {
        var onScroll: ((Double) -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let onScroll, let window, event.window === window, !isHiddenOrHasHiddenAncestor,
                  bounds.contains(convert(event.locationInWindow, from: nil)) else { return event }
            // A trackpad's coasting after the fingers lift would overshoot; the gesture itself is enough.
            guard event.momentumPhase.isEmpty else { return nil }
            var delta = event.scrollingDeltaY
            if event.isDirectionInvertedFromDevice { delta = -delta }
            // Trackpads and smooth wheels report pixels; about 10 of them make a notch.
            let notches = event.hasPreciseScrollingDeltas ? delta / 10 : delta
            if notches != 0 { onScroll(notches) }
            return nil
        }
    }
}

public struct Segmented<Option: Hashable>: View {
    public let options: [Option]
    @Binding public var selection: Option
    public let title: (Option) -> String
    /// The profile picker fills its row; the compact one hugs its labels.
    public var stretch = false

    public init(options: [Option], selection: Binding<Option>, title: @escaping (Option) -> String, stretch: Bool = false) {
        self.options = options
        self._selection = selection
        self.title = title
        self.stretch = stretch
    }

    @Namespace private var pill

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
                Text(title(option))
                    .lineLimit(1)
                    .font(.display(12, selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.text : Theme.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .frame(maxWidth: stretch ? .infinity : nil)
                    .background {
                        if selected {
                            shape.fill(Theme.segmentSelected)
                                .shadow(color: Color.black.opacity(0.12), radius: 1.5, y: 1)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option }
            }
        }
        // Only the pill slides; whatever the selection swaps in elsewhere changes instantly.
        .animation(Motion.slide, value: selection)
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.segmentTrack))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))

    }
}

// MARK: - Chips

/// Translucent pill token with JetBrains Mono text.
public struct Chip: View {
    public enum Tone {
        case emerald, amber, solar, magenta, violet, neutral

        public var color: Color {
            switch self {
            case .emerald: return Theme.emerald
            case .amber: return Theme.amber
            case .solar: return Theme.solar
            case .magenta: return Theme.magenta
            case .violet: return Theme.violet
            case .neutral: return Theme.text
            }
        }

        public var text: Color {
            switch self {
            case .emerald: return Color.dynamic(dark: 0x6EE7B7, light: 0x047857)
            case .amber: return Color.dynamic(dark: 0xFCD34D, light: 0xB45309)
            case .solar: return Theme.solarLight
            case .magenta: return Theme.magentaLight
            case .violet: return Theme.violetLight
            case .neutral: return Theme.textMuted
            }
        }
    }

    public let text: String
    public var tone: Tone = .neutral
    public var dot = false

    public init(_ text: String, tone: Tone = .neutral, dot: Bool = false) {
        self.text = text
        self.tone = tone
        self.dot = dot
    }

    public var body: some View {
        HStack(spacing: 5) {
            if dot {
                Circle().fill(tone.color).frame(width: 5, height: 5).shadow(color: tone.color.opacity(0.9), radius: 3)
            }
            Text(text).font(.mono(10)).tracking(0.3)
        }
        .foregroundStyle(tone.text)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tone.color.opacity(tone == .neutral ? 0.05 : 0.15)))
        .overlay(Capsule().strokeBorder(tone.color.opacity(tone == .neutral ? 0.1 : 0.35)))
        .fixedSize()
    }

    /// Marks settings whose behavior isn't implemented yet.
    public static var soon: Chip { Chip(L("Coming soon")) }
}

public struct KeyCap: View {
    public let text: String

    public init(text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(.mono(10))
            .foregroundStyle(Theme.magentaLight)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Theme.magenta.opacity(0.15)))
            .overlay(Capsule().strokeBorder(Theme.magenta.opacity(0.35)))
            .fixedSize()
    }
}

// MARK: - Buttons

/// Solar→violet gradient with an inset highlight and an orange outer glow.
public struct PrimaryButtonStyle: ButtonStyle {
    /// Shorter variant for inline controls that must not change a row's height.
    public var compact = false

    public init(compact: Bool = false) { self.compact = compact }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous)
        return configuration.label
            .font(.ui(compact ? 11 : 12, .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 3 : 6)
            .background(shape.fill(LinearGradient(colors: [Theme.solar, Theme.magenta], startPoint: .leading, endPoint: .trailing)))
            .overlay(shape.strokeBorder(LinearGradient(colors: [Theme.tint(0.3), Theme.tint(0.05)],
                                                       startPoint: .top, endPoint: .bottom)))
            .shadow(color: Theme.solar.opacity(configuration.isPressed ? 0.6 : 0.35), radius: 8)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
            .fixedSize()
    }
}

/// Obsidian glass with a 1px hairline.
public struct GhostButtonStyle: ButtonStyle {
    public var tint: Color = Theme.text
    public var compact = false

    public init(tint: Color = Theme.text, compact: Bool = false) {
        self.tint = tint
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous)
        return configuration.label
            .font(.ui(compact ? 11 : 12, .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 3 : 6)
            .background(shape.fill(Theme.tint(configuration.isPressed ? 0.1 : 0.04)))
            .overlay(shape.strokeBorder(configuration.isPressed ? Theme.magenta : Theme.tint(0.1)))
            .contentShape(Rectangle())
            .fixedSize()
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

public extension ButtonStyle where Self == GhostButtonStyle {
    static var ghost: GhostButtonStyle { GhostButtonStyle() }
}

// MARK: - Rows & layout

/// Title + detail on the left, a control on the right.
/// Title block for a settings card: tinted icon tile, title and a short line about the card,
/// separated from the rows below by a hairline.
public struct CardHeader<Trailing: View>: View {
    public let symbol: String
    public let title: String
    public var subtitle: String?
    public var tint: Color = Theme.violet
    @ViewBuilder public let trailing: Trailing

    public init(symbol: String, title: String, subtitle: String? = nil, tint: Color = Theme.violet,
                @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                GlyphTile(tint: tint, size: 34) {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.display(16, .semibold)).tracking(-0.2).foregroundStyle(Theme.text)
                    if let subtitle {
                        Text(subtitle).font(.ui(11)).foregroundStyle(Theme.textMuted)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
            Hairline()
        }
    }
}

public struct SettingRow<Accessory: View>: View {
    public let title: String
    public let detail: String
    public var soon = false
    @ViewBuilder public let accessory: Accessory

    public init(title: String, detail: String, soon: Bool = false, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.detail = detail
        self.soon = soon
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.ui(13, .medium)).foregroundStyle(Theme.text)
                    if soon { Chip.soon }
                }
                Text(detail)
                    .font(.ui(12))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            accessory
        }
    }
}

/// ScrollView with the system scroller hidden and a slim themed one drawn on top.
/// It appears while scrolling or hovering and fades out shortly after. The thumb sits in the pages'
/// side padding, so the content keeps the same width whether or not it overflows.
public struct SlimScrollView<Content: View>: View {
    public var contentHeight: Binding<CGFloat>?
    public var scrollTarget: UUID?
    /// Changing this jumps back to the top, e.g. when another page is shown in the same scroll view.
    public var resetID: AnyHashable?
    /// Room kept on the right for the thumb, for content that runs edge to edge (pages have their own padding).
    public var gutter: CGFloat = 0
    @ViewBuilder public let content: Content

    public init(contentHeight: Binding<CGFloat>? = nil, scrollTarget: UUID? = nil, resetID: AnyHashable? = nil,
                gutter: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.contentHeight = contentHeight
        self.scrollTarget = scrollTarget
        self.resetID = resetID
        self.gutter = gutter
        self.content = content()
    }

    @State private var metrics = ScrollMetrics()
    @State private var viewport: CGFloat = 0
    @State private var hovering = false
    @State private var scrolling = false
    @State private var fadeTask: DispatchWorkItem?
    private let space = "slim-scroll"
    private static var topAnchor: String { "slim-scroll-top" }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id(Self.topAnchor)
                    content
                }
                .padding(.trailing, gutter)
                    .background(GeometryReader { geometry in
                    Color.clear.preference(key: ScrollMetricsKey.self, value: ScrollMetrics(
                        height: geometry.size.height,
                        offset: -geometry.frame(in: .named(space)).minY))
                })
            }
            .coordinateSpace(name: space)
            .scrollIndicators(.never)
            .onChange(of: resetID) { _ in proxy.scrollTo(Self.topAnchor, anchor: .top) }
            .onChange(of: scrollTarget) { target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(target, anchor: .center) }
            }
        }
        .onPreferenceChange(ScrollMetricsKey.self) { new in
            let moved = abs(new.offset - metrics.offset) > 0.5
            metrics = new
            contentHeight?.wrappedValue = new.height
            if moved { flash() }
        }
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { viewport = geometry.size.height }
                .onChange(of: geometry.size.height) { viewport = $0 }
        })
        .overlay(alignment: .topTrailing) { thumb }
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var thumb: some View {
        let overflow = metrics.height - viewport
        if overflow > 1, viewport > 0 {
            let inset: CGFloat = 4
            let track = viewport - inset * 2
            let length = max(28, track * viewport / metrics.height)
            let progress = min(max(metrics.offset / overflow, 0), 1)
            let visible = scrolling || hovering
            // Plain silver grey, a little stronger on hover.
            Capsule()
                .fill(Theme.tint(hovering ? 0.42 : 0.28))
                .frame(width: hovering ? 6 : 4, height: length)
                .offset(x: -8, y: inset + progress * (track - length))
                .opacity(visible ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: visible)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .allowsHitTesting(false)
        }
    }

    private func flash() {
        scrolling = true
        fadeTask?.cancel()
        let task = DispatchWorkItem { scrolling = false }
        fadeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: task)
    }
}

struct ScrollMetrics: Equatable {
    var height: CGFloat = 0
    var offset: CGFloat = 0
}

private struct ScrollMetricsKey: PreferenceKey {
    static var defaultValue = ScrollMetrics()

    static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) {
        let next = nextValue()
        if next.height > value.height { value = next }
    }
}

/// One choice in a `Dropdown`.
public struct DropdownItem: Identifiable {
    public let id: String
    public let title: String
    public var detail: String?
    public var symbol: String?
    public var selected = false
    public let action: () -> Void

    public init(id: String, title: String, detail: String? = nil, symbol: String? = nil, selected: Bool = false,
                action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.selected = selected
        self.action = action
    }
}

/// A themed dropdown: the label opens a popover listing the choices, grouped into sections.
public struct Dropdown<Label: View>: View {
    public let sections: [[DropdownItem]]
    public var width: CGFloat = 260
    @ViewBuilder public let label: () -> Label
    @State private var open = false

    public init(sections: [[DropdownItem]], width: CGFloat = 260, @ViewBuilder label: @escaping () -> Label) {
        self.sections = sections
        self.width = width
        self.label = label
    }

    public var body: some View {
        Button { open.toggle() } label: { label() }
            .buttonStyle(.plain)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sections.indices, id: \.self) { index in
                        if index > 0 { Hairline().padding(.vertical, 2) }
                        ForEach(sections[index]) { item in
                            DropdownRow(item: item) {
                                open = false
                                item.action()
                            }
                        }
                    }
                }
                .padding(6)
                .frame(width: width)
                .background(Theme.popoverTop)
            }
    }
}

private struct DropdownRow: View {
    public let item: DropdownItem
    public let action: () -> Void
    @State private var hovering = false

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol = item.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(item.selected || hovering ? Theme.solar : Theme.violet)
                        .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.ui(12, item.selected ? .semibold : .medium))
                        .foregroundStyle(item.selected ? Theme.solar : Theme.text)
                        .lineLimit(1)
                    if let detail = item.detail {
                        Text(detail).font(.ui(10)).foregroundStyle(Theme.textMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if item.selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.solar)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(item.selected ? Theme.tint(0.06) : hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
