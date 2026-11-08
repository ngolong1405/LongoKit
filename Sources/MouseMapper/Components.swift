import CoreText
import SwiftUI

// Tokens from the "Solar Sunset & Cyber-Violet" design token system. Every color resolves per
// appearance, so the whole UI follows the Light/Dark setting (or macOS when set to System).

enum Theme {
    static let windowWidth: CGFloat = 900
    /// Height of the page area between the tab bar and the footer, the same on every tab.
    static let contentHeight: CGFloat = 700
    static let windowRadius: CGFloat = 16

    // Accents
    static let solar = Color.dynamic(dark: 0xFF6B35, light: 0xEE5A22)
    /// Solar Flame on dark, Solar Deep on light: readable accent text in both.
    static let solarLight = Color.dynamic(dark: 0xFFA26B, light: 0xD94814)
    static let violet = Color.dynamic(dark: 0x8B5CF6, light: 0x7C3AED)
    static let violetLight = Color.dynamic(dark: 0xA78BFA, light: 0x6D28D9)
    /// Secondary highlight (listening, picked tiles); same Cyber-Violet family.
    static let magenta = violet
    static let magentaLight = violetLight
    static let accentGradient = LinearGradient(colors: [solar, violet], startPoint: .topLeading, endPoint: .bottomTrailing)

    // Status
    static let emerald = Color.dynamic(dark: 0x10B981, light: 0x059669)
    static let amber = Color.dynamic(dark: 0xF59E0B, light: 0xD97706)
    static let danger = Color.dynamic(dark: 0xEF4444, light: 0xDC2626)
    static let info = Color(hex: 0x06B6D4)

    // Surfaces
    static let canvas = Color.dynamic(dark: 0x0B0C10, light: 0xF5F6F8)
    static let canvasTop = Color.dynamic(dark: 0x121319, light: 0xFFFFFF)
    static let pane = Color.dynamic(dark: 0x161820, light: 0xF8F9FA, darkOpacity: 0.72, lightOpacity: 0.9)
    static let island = Color.dynamic(dark: 0x1A1B22, light: 0xFFFFFF, darkOpacity: 0.85, lightOpacity: 0.94)
    static let well = Color.dynamic(dark: 0x0C0E13, light: 0xE9EBEF, darkOpacity: 0.8, lightOpacity: 1)
    static let hover = Color.dynamic(dark: 0x242632, light: 0xEDF0F5)
    static let slate = Color.dynamic(dark: 0x2F3242, light: 0xE1E5ED)
    /// Footer and other chrome strips.
    static let chrome = Color.dynamic(dark: 0x000000, light: 0x000000, darkOpacity: 0.25, lightOpacity: 0.03)
    static let popoverTop = Color.dynamic(dark: 0x1B1A24, light: 0xFFFFFF)
    static let popoverBottom = Color.dynamic(dark: 0x0B0C10, light: 0xF5F6F8)
    static let showcaseTop = Color.dynamic(dark: 0x2A1A26, light: 0xFFF1EA)
    static let showcaseBottom = Color.dynamic(dark: 0x16131D, light: 0xF4EEFF)
    static let listenTop = Color.dynamic(dark: 0x241A3A, light: 0xF1EAFF)
    static let listenBottom = Color.dynamic(dark: 0x16121F, light: 0xFBF8FF)
    static let segmentTrack = Color.dynamic(dark: 0x0C0E13, light: 0xE6E8EC, darkOpacity: 0.8, lightOpacity: 1)
    static let segmentSelected = Color.dynamic(dark: 0x2F3242, light: 0xFFFFFF)
    /// Soft card elevation (`--shadow-card`).
    static let cardShadow = Color.dynamic(dark: 0x000000, light: 0x000000, darkOpacity: 0.35, lightOpacity: 0.07)
    static let innerShadow = Color.dynamic(dark: 0x000000, light: 0x000000, darkOpacity: 0.6, lightOpacity: 0.12)

    // Borders
    static let hairline = Color.dynamic(dark: 0xFFFFFF, light: 0x000000, darkOpacity: 0.08, lightOpacity: 0.08)
    static let borderProminent = Color.dynamic(dark: 0xFFFFFF, light: 0x000000, darkOpacity: 0.16, lightOpacity: 0.14)
    static let rim = LinearGradient(
        colors: [Color.dynamic(dark: 0xFFFFFF, light: 0x000000, darkOpacity: 0.14, lightOpacity: 0.1),
                 Color.dynamic(dark: 0xFFFFFF, light: 0x000000, darkOpacity: 0.04, lightOpacity: 0.06)],
        startPoint: .top, endPoint: .bottom)
    static let cardRim = LinearGradient(colors: [solar.opacity(0.3), violet.opacity(0.3)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)

    // Text
    static let text = Color.dynamic(dark: 0xF3F4F6, light: 0x111827)
    static let textSecondary = Color.dynamic(dark: 0xD1D5DB, light: 0x374151)
    static let textMuted = Color.dynamic(dark: 0x9CA3AF, light: 0x4B5563)
    static let textFaint = Color.dynamic(dark: 0x6B7280, light: 0x9CA3AF)

    /// Neutral overlay that reads on both themes: white on dark, black on light.
    static func tint(_ opacity: Double) -> Color {
        Color.dynamic(dark: 0xFFFFFF, light: 0x000000, darkOpacity: opacity, lightOpacity: opacity * 0.7)
    }
}

/// Shared animation curves so every transition in the app feels the same.
enum Motion {
    /// Selection pills sliding between options.
    static let slide = Animation.spring(response: 0.3, dampingFraction: 0.86)
    /// Rows appearing, disappearing or reordering.
    static let list = Animation.spring(response: 0.34, dampingFraction: 0.88)
    /// Small state swaps such as hover or edit mode.
    static let quick = Animation.easeOut(duration: 0.15)
    /// Inserted rows fade and drop in; removed rows fade out.
    static let row = AnyTransition.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)), removal: .opacity)
}

enum AppAppearance: String, CaseIterable, Codable {
    case system, dark, light

    var title: String {
        switch self {
        case .system: return L("System")
        case .light: return L("Light")
        case .dark: return L("Dark")
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

extension Color {
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

extension Font {
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

enum Fonts {
    /// Registers the bundled OFL fonts for this process. Missing files fall back to the system font.
    static func register() {
        for name in ["SpaceGrotesk", "Geist", "JetBrainsMono"] {
            if let url = Resource.url(for: "Fonts/\(name).ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

extension View {
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

struct Hairline: View {
    var color: Color = Theme.hairline

    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

/// Uppercase JetBrains Mono micro label ("STARTUP & BEHAVIOR").
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.mono(10, .medium))
            .tracking(0.5)
            .foregroundStyle(Theme.textFaint)
    }
}

// MARK: - Resources & icons

enum Resource {
    private static var imageCache: [String: NSImage] = [:]

    /// `Contents/Resources/<path>`, falling back to `Support/<path>` when run via `swift run`.
    static func url(for path: String) -> URL? {
        if let resources = Bundle.main.resourceURL {
            let url = resources.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Support/\(path)")
            .standardized
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }

    static func image(_ path: String, template: Bool = false) -> NSImage? {
        let key = template ? path + "#template" : path
        if let cached = imageCache[key] { return cached }
        guard let url = url(for: path), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = template
        imageCache[key] = image
        return image
    }
}

/// Rounded tile holding a glyph, tinted with an accent.
struct GlyphTile<Glyph: View>: View {
    var tint: Color = Theme.violet
    var size: CGFloat = 32
    @ViewBuilder let glyph: Glyph

    var body: some View {
        glyph
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tint.opacity(0.35)))
    }
}

// MARK: - Controls

/// Sequoia toggle: muted slate when off, bursting into Solar Amber with an ambient glow when on.
struct DSSwitch: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
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

extension DSSwitch {
    init(isOn: Binding<Bool>) {
        self.init(isOn: isOn.wrappedValue) { isOn.wrappedValue.toggle() }
    }
}

struct DSCheckbox: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
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
struct DSSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01

    var body: some View {
        GeometryReader { geometry in
            let travel = geometry.size.width - 18
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Color.clear.frame(height: 6).recessed(radius: 3)
                Capsule()
                    .fill(Theme.accentGradient)
                    .frame(width: max(travel * fraction + 9, 6), height: 6)
                    .shadow(color: Theme.solar.opacity(0.5), radius: 5)
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
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let f = min(max((drag.location.x - 9) / travel, 0), 1)
                let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
                value = (raw / step).rounded() * step
            })
        }
        .frame(height: 18)
    }
}

struct Segmented<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    /// The profile picker fills its row; the compact one hugs its labels.
    var stretch = false

    @Namespace private var pill

    var body: some View {
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
struct Chip: View {
    enum Tone {
        case emerald, amber, solar, magenta, violet, neutral

        var color: Color {
            switch self {
            case .emerald: return Theme.emerald
            case .amber: return Theme.amber
            case .solar: return Theme.solar
            case .magenta: return Theme.magenta
            case .violet: return Theme.violet
            case .neutral: return Theme.text
            }
        }

        var text: Color {
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

    let text: String
    var tone: Tone = .neutral
    var dot = false

    init(_ text: String, tone: Tone = .neutral, dot: Bool = false) {
        self.text = text
        self.tone = tone
        self.dot = dot
    }

    var body: some View {
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
    static var soon: Chip { Chip(L("Coming soon")) }
}

struct KeyCap: View {
    let text: String

    var body: some View {
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
struct PrimaryButtonStyle: ButtonStyle {
    /// Shorter variant for inline controls that must not change a row's height.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
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
struct GhostButtonStyle: ButtonStyle {
    var tint: Color = Theme.text
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
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

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static var ghost: GhostButtonStyle { GhostButtonStyle() }
}

// MARK: - Rows & layout

/// Title + detail on the left, a control on the right.
/// Title block for a settings card: tinted icon tile, title and a short line about the card,
/// separated from the rows below by a hairline.
struct CardHeader<Trailing: View>: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var tint: Color = Theme.violet
    @ViewBuilder let trailing: Trailing

    var body: some View {
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

struct SettingRow<Accessory: View>: View {
    let title: String
    let detail: String
    var soon = false
    @ViewBuilder let accessory: Accessory

    var body: some View {
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
struct SlimScrollView<Content: View>: View {
    var contentHeight: Binding<CGFloat>?
    var scrollTarget: UUID?
    /// Changing this jumps back to the top, e.g. when another page is shown in the same scroll view.
    var resetID: AnyHashable?
    /// Room kept on the right for the thumb, for content that runs edge to edge (pages have their own padding).
    var gutter: CGFloat = 0
    @ViewBuilder let content: Content

    @State private var metrics = ScrollMetrics()
    @State private var viewport: CGFloat = 0
    @State private var hovering = false
    @State private var scrolling = false
    @State private var fadeTask: DispatchWorkItem?
    private let space = "slim-scroll"
    private static var topAnchor: String { "slim-scroll-top" }

    var body: some View {
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

/// A device name that turns into a text field in place, with Save and Cancel, when its edit icon is clicked.
struct InlineRename: View {
    @EnvironmentObject private var model: AppModel
    let deviceID: String
    var font: Font = .display(14, .semibold)
    var color: Color = Theme.text

    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var frame: CGRect = .zero
    @State private var clickMonitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            if editing {
                Group {
                TextField(model.profiles[deviceID]?.product ?? "", text: $text)
                    .textFieldStyle(.plain)
                    .font(font)
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 110, maxWidth: 220, minHeight: 24, maxHeight: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.segmentTrack))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.solar.opacity(0.7)))
                    .focused($focused)
                    .onSubmit(save)
                    .onExitCommand(perform: cancel)
                Button(L("Save"), action: save).buttonStyle(PrimaryButtonStyle(compact: true))
                Button(L("Cancel"), action: cancel).buttonStyle(GhostButtonStyle(compact: true))
                }
                .transition(.opacity)
            } else {
                Text(model.displayName(deviceID)).font(font).foregroundStyle(color).lineLimit(1)
                Button(action: begin) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.solar)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.solar.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.solar.opacity(0.3)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Rename this mouse"))
            }
        }
        // Same height whether showing the name or the field, so nothing below shifts.
        .frame(height: 26)
        .animation(Motion.quick, value: editing)
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { frame = geometry.frame(in: .global) }
                .onChange(of: geometry.frame(in: .global)) { frame = $0 }
        })
        // Leaving the field (tabbing away, switching apps, closing the page) ends editing without saving.
        .onChange(of: focused) { isFocused in
            if !isFocused && editing { cancel() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if editing { cancel() }
        }
        .onDisappear(perform: stopWatchingClicks)
    }

    private func begin() {
        text = model.displayName(deviceID)
        editing = true
        DispatchQueue.main.async { focused = true }
        watchClicks()
    }

    /// Clicking empty parts of the window doesn't take focus from a text field, so clicks outside
    /// the field and its buttons are watched for directly.
    private func watchClicks() {
        stopWatchingClicks()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            if let content = event.window?.contentView {
                let point = content.convert(event.locationInWindow, from: nil)
                let flipped = content.isFlipped ? point : CGPoint(x: point.x, y: content.bounds.height - point.y)
                if !frame.insetBy(dx: -4, dy: -4).contains(flipped) { cancel() }
            }
            return event
        }
    }

    private func stopWatchingClicks() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    private func save() {
        let name = text.trimmingCharacters(in: .whitespaces)
        // Saving the original product name (or nothing) goes back to the default name.
        model.setNickname(deviceID, name == model.profiles[deviceID]?.product ? nil : name)
        editing = false
        stopWatchingClicks()
    }

    private func cancel() {
        editing = false
        stopWatchingClicks()
    }
}

/// One choice in a `Dropdown`.
struct DropdownItem: Identifiable {
    let id: String
    let title: String
    var detail: String?
    var symbol: String?
    var selected = false
    let action: () -> Void
}

/// A themed dropdown: the label opens a popover listing the choices, grouped into sections.
struct Dropdown<Label: View>: View {
    let sections: [[DropdownItem]]
    var width: CGFloat = 260
    @ViewBuilder let label: () -> Label
    @State private var open = false

    var body: some View {
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
    let item: DropdownItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
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
