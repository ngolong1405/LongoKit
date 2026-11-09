import LongoKitUI
import SwiftUI

/// Every connected display; picking one opens its page.
struct DisplaysTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let key = model.openDisplayKey, let display = model.displays.first(where: { $0.key == key }) {
                DisplayPage(display: display)
            } else {
                DisplayList()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

extension Display {
    /// "3840 × 2160", without locale digit grouping.
    var sizeLabel: String { "\(Int(pixelSize.width)) × \(Int(pixelSize.height))" }
}

extension ControlChoice {
    var title: String {
        switch self {
        case .hardware: return L("Hardware (DDC)")
        case .software: return L("Software")
        }
    }
}

extension ControlMethod {
    var title: String {
        switch self {
        case .native: return L("Native")
        case .ddc: return "DDC/CI"
        case .software: return L("Software")
        }
    }

    var detail: String {
        switch self {
        case .native: return L("Controlled by macOS")
        case .ddc: return L("Hardware brightness over the cable")
        case .software: return L("No DDC: dimmed in software")
        }
    }

    var tone: Chip.Tone {
        switch self {
        case .native: return .emerald
        case .ddc: return .violet
        case .software: return .amber
        }
    }
}

// MARK: - List

private struct DisplayList: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: L("Connected displays") + " (\(model.displays.count))")
            VStack(spacing: 0) {
                ForEach(Array(model.displays.enumerated()), id: \.element.key) { index, display in
                    if index > 0 { Hairline() }
                    DisplayRow(display: display)
                }
            }
            .panel(padding: 0)
            if model.externals.isEmpty {
                Text(L("Connect an external display to control its brightness."))
                    .font(.ui(12))
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
            }
        }
    }
}

private struct DisplayRow: View {
    @EnvironmentObject private var model: AppModel
    let display: Display

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 12) {
            Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                .font(.system(size: 16))
                .foregroundStyle(Theme.violetLight)
                .frame(width: 38, height: 38)
                .recessed(radius: 10)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.displayName(display)).font(.display(14, .semibold)).foregroundStyle(Theme.text)
                    if model.isOn(display) {
                        Chip(display.method.title, tone: display.method.tone)
                    } else {
                        Chip(L("Off"))
                    }
                }
                Text(!model.isOn(display) ? L("Turned off: windows moved to your other displays")
                     : display.sizeLabel + " · " + display.method.detail)
                    .font(.ui(11))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            PowerButton(display: display)
            Button { model.openDisplayKey = display.key } label: {
                HStack(spacing: 4) {
                    Text(L("Customize"))
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                }
            }
            .buttonStyle(.ghost)
        }
            if model.isOn(display) {
                QuickBrightness(display: display)
            }
        }
        .padding(14)
    }
}

/// Brightness right in the list. Locked for external displays in Sync, where they follow the built-in one.
private struct QuickBrightness: View {
    @EnvironmentObject private var model: AppModel
    let display: Display

    var body: some View {
        DisplayLevels(display: display, columns: true)
            .padding(.leading, 50)
    }
}

/// A display's everyday levels: brightness; extra dimming once brightness reaches 0% (like Lunar's sub-zero
/// dimming); and its speakers (DDC for a monitor, the Mac's output volume for the built-in display).
struct DisplayLevels: View {
    @EnvironmentObject private var model: AppModel
    let display: Display
    /// Side by side (the window's list) or stacked (the menu).
    let columns: Bool

    var body: some View {
        let locked = model.mode == .sync && !display.isBuiltin
        let layout = columns ? AnyLayout(HStackLayout(alignment: .top, spacing: 24)) : AnyLayout(VStackLayout(spacing: 8))
        layout {
            BrightnessLevel(display: display)
                .disabled(locked)
                .opacity(locked ? 0.5 : 1)
                .help(locked ? L("Follows the built-in display in Sync mode") : L("Brightness"))
            if display.method == .ddc {
                VolumeSlider(value: model.volume(for: display), help: L("Speaker volume")) { model.setVolume($0, for: display) }
            } else if display.isBuiltin, let volume = model.systemVolume {
                VolumeSlider(value: volume, help: L("Mac volume")) { model.setSystemVolume($0) }
            }
        }
    }
}

/// Brightness and extra dimming on one slider: right of the 0 tick is the backlight, left of it (violet, with a
/// moon) darkens the picture further. Displays dimmed in software only go down to 0.
struct BrightnessLevel: View {
    @EnvironmentObject private var model: AppModel
    let display: Display

    var body: some View {
        let level = model.settings(for: display).level
        let range = model.levelRange(for: display)
        let dimming = level < 0
        HStack(spacing: 8) {
            Image(systemName: dimming ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 11))
                .foregroundStyle(dimming ? Theme.violetLight : Theme.solar)
                .frame(width: 16)
            StepButton(symbol: "minus") { model.setLevel(level - StepButton.step, for: display) }
            DSSlider(value: Binding(get: { level }, set: { model.setLevel($0, for: display) }), range: range, step: 0.01,
                     origin: range.lowerBound < 0 ? 0 : nil, label: "\(Int((level * 100).rounded()))%")
            StepButton(symbol: "plus") { model.setLevel(level + StepButton.step, for: display) }
        }
    }
}

/// Speaker volume, set apart from brightness: a thin cyan slider with the percentage after it. The speaker icon
/// mutes, and unmutes back to where it was.
struct VolumeSlider: View {
    let value: Double
    let help: String
    let set: (Double) -> Void
    /// The level before muting, to come back to.
    @State private var beforeMute: Double?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if value > 0 {
                    beforeMute = value
                    set(0)
                } else {
                    set(beforeMute ?? 0.5)
                    beforeMute = nil
                }
            } label: {
                Image(systemName: value > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(value > 0 ? Theme.info : Theme.textMuted)
                    .frame(width: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(value > 0 ? L("Mute") : L("Unmute"))
            DSSlider(value: Binding(get: { value }, set: set), range: 0...1, step: 0.01, accent: Theme.info)
                .padding(.leading, StepButton.size + 8)
            Text("\(Int((value * 100).rounded()))%")
                .font(.mono(10, .semibold))
                .foregroundStyle(Theme.info)
                .frame(width: StepButton.size + 8, alignment: .trailing)
        }
        .help(help)
    }
}

/// − / + at the ends of a slider, for 5% at a time without dragging.
struct StepButton: View {
    static let step = 0.05
    static let size: CGFloat = 20
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Self.size, height: Self.size)
                .background(Circle().fill(Theme.tint(0.07)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(symbol == "plus" ? L("Up 5%") : L("Down 5%"))
    }
}

/// A 0…1 level with its icon in front and the percentage after: brightness, volume.
struct LevelSlider: View {
    let symbol: String
    let value: Double
    var tint = Theme.solar
    let set: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .frame(width: 16)
            StepButton(symbol: "minus") { set(max(value - StepButton.step, 0)) }
            DSSlider(value: Binding(get: { value }, set: set), range: 0...1, step: 0.01, label: "\(Int((value * 100).rounded()))%")
            StepButton(symbol: "plus") { set(min(value + StepButton.step, 1)) }
        }
    }
}

// MARK: - Display page

/// One display: the screen with its brightness in the middle, minimum and maximum on either side.
private struct DisplayPage: View {
    @EnvironmentObject private var model: AppModel
    let display: Display

    var body: some View {
        let value = model.settings(for: display)
        VStack(alignment: .leading, spacing: 16) {
            Button { model.openDisplayKey = nil } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                    Text(L("Displays"))
                }
                .font(.ui(12, .medium))
                .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)

            PageHeader(display: display)

            Group {
                ScreenCard(display: display, value: value)
                HStack(alignment: .top, spacing: 14) {
                    if display.isBuiltin {
                        SyncSourceCard()
                    } else {
                        if display.hasDDC {
                            ControlCard(display: display)
                        } else {
                            SoftwareCard()
                        }
                        SyncRangeCard(display: display)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!model.isOn(display))
            .opacity(model.isOn(display) ? 1 : 0.4)

            HStack {
                Spacer()
                Button { model.resetDisplay(display) } label: { Label(L("Reset this display"), systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.ghost)
            }
        }
    }
}

/// The display's name and kind, with its power switch and how to get it back.
private struct PageHeader: View {
    @EnvironmentObject private var model: AppModel
    let display: Display

    var body: some View {
        let on = model.isOn(display)
        let locked = on && !model.canTurnOff(display)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                GlyphTile(tint: on ? Theme.violet : Theme.slate, size: 44) {
                    Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(on ? Theme.violet : Theme.textMuted)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.displayName(display))
                        .font(.display(20, .bold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if on {
                            Chip(display.method.title, tone: display.method.tone, dot: true)
                        } else {
                            Chip(L("Off"))
                        }
                        if display.pixelSize != .zero { Chip(display.sizeLabel) }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    DSSwitch(isOn: on) { model.setPower(display, on: !on) }
                        .disabled(locked)
                        .opacity(locked ? 0.4 : 1)
                    Text(on ? L("On") : L("Off")).font(.mono(10, .semibold)).foregroundStyle(Theme.textFaint)
                }
                .help(L("Off works like unplugging it: windows move to your other displays."))
            }
            Text(locked ? L("The last display that's on can't be turned off")
                 : L("Turning it off asks to keep it off; with no answer it comes back in %d seconds. ⌃⌥⌘B turns every display back on.", PowerConfirmation.seconds))
                .font(.ui(11))
                .foregroundStyle(Theme.textMuted)
        }
        .panel()
    }
}

/// A monitor without DDC: what Software dimming means for it.
private struct SoftwareCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "circle.lefthalf.filled", title: L("Software dimming"),
                       subtitle: L("This monitor doesn't take DDC, so its picture is darkened instead of its backlight."),
                       tint: Theme.amber, divider: false) { EmptyView() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panel()
    }
}

/// The built-in display drives Sync: every external display and the range it follows it in.
private struct SyncSourceCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let builtinValue = model.builtin.map { model.settings(for: $0).brightness } ?? 0
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "link", title: L("Drives Sync"),
                       subtitle: L("In Sync, external displays follow this display's brightness, each within its own range."),
                       tint: Theme.violet) {
                if model.mode == .sync {
                    Chip(L("On"), tone: .emerald, dot: true)
                } else {
                    Button(L("Use Sync")) { model.mode = .sync }.buttonStyle(.ghost)
                }
            }
            if model.externals.isEmpty {
                Text(L("Connect an external display to control its brightness."))
                    .font(.ui(12)).foregroundStyle(Theme.textMuted)
            }
            ForEach(model.externals) { display in
                let value = model.settings(for: display)
                HStack(spacing: 10) {
                    Image(systemName: "display").foregroundStyle(Theme.violetLight)
                    Text(model.displayName(display)).font(.ui(12, .medium)).foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(Int((value.minimum * 100).rounded()))–\(Int((value.maximum * 100).rounded()))%")
                        .font(.mono(11)).foregroundStyle(Theme.textMuted)
                    Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textFaint)
                    Text("\(Int((SyncMath.map(builtin: builtinValue, minimum: value.minimum, maximum: value.maximum) * 100).rounded()))%")
                        .font(.mono(11, .semibold)).foregroundStyle(Theme.solar)
                        .frame(width: 40, alignment: .trailing)
                    Button { model.openDisplayKey = display.key } label: {
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.ghost)
                    .help(L("Customize"))
                }
            }
        }
        .panel()
    }
}

/// Hardware (DDC) or software dimming, for monitors that have DDC.
private struct ControlCard: View {
    @EnvironmentObject private var model: AppModel
    let display: Display

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "slider.horizontal.3", title: L("Brightness Control"),
                       subtitle: L("Hardware changes the monitor's backlight; Software darkens the picture."),
                       tint: Theme.violet) { EmptyView() }
            Segmented(options: ControlChoice.allCases,
                      selection: Binding(get: { model.settings(for: display).control },
                                         set: { model.setControl(display, $0) }),
                      title: \.title, stretch: true)
            if model.isDDCSilent(display) {
                Text(L("This monitor takes DDC commands but doesn't report its brightness back (common on a MacBook's HDMI port), so the app can't read where it starts. If moving the slider doesn't change it, choose Software."))
                    .font(.ui(11))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panel()
    }
}


private struct ScreenCard: View {
    @EnvironmentObject private var model: AppModel
    let display: Display
    let value: DisplaySettings

    var body: some View {
        VStack(spacing: 0) {
            // The name and kind are in the page header; the screen holds the levels.
            VStack(spacing: 14) {
                BrightnessLevel(display: display)
                    // In Sync an external display follows the built-in one, as in the menu.
                    .disabled(model.mode == .sync && !display.isBuiltin)
                    .opacity(model.mode == .sync && !display.isBuiltin ? 0.5 : 1)
                    .help(model.mode == .sync && !display.isBuiltin ? L("Follows the built-in display in Sync mode") : "")
                if display.method == .ddc {
                    VolumeSlider(value: model.volume(for: display), help: L("Speaker volume")) { model.setVolume($0, for: display) }
                } else if display.isBuiltin, let volume = model.systemVolume {
                    VolumeSlider(value: volume, help: L("Mac volume")) { model.setSystemVolume($0) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.well))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderProminent, lineWidth: 6))
            // Stand
            Rectangle().fill(Theme.slate).frame(width: 60, height: 18)
            RoundedRectangle(cornerRadius: 3).fill(Theme.slate).frame(width: 130, height: 6)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Sync for an external display: the range it moves through as the built-in display goes from 0% to 100%, with
/// a live example. Only Sync uses it, which it says when the app is in Manual.
private struct SyncRangeCard: View {
    @EnvironmentObject private var model: AppModel
    let display: Display

    var body: some View {
        let value = model.settings(for: display)
        let builtinValue = model.builtin.map { model.settings(for: $0).brightness } ?? 0.5
        let mapped = SyncMath.map(builtin: builtinValue, minimum: value.minimum, maximum: value.maximum)
        let syncing = model.mode == .sync
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(symbol: "link", title: L("Sync with the MacBook"),
                       subtitle: L("In Sync, this display follows the MacBook's brightness, within this range."),
                       tint: Theme.violet) {
                if syncing {
                    Chip(L("On"), tone: .emerald, dot: true)
                } else {
                    Button(L("Use Sync")) { model.mode = .sync }.buttonStyle(.ghost)
                }
            }
            RangeSlider(low: value.minimum, high: value.maximum) { low, high in
                model.setSyncRange(low, high, for: display)
            }
            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer").foregroundStyle(Theme.textMuted)
                Text("MacBook \(Int((builtinValue * 100).rounded()))%")
                Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textFaint)
                Image(systemName: "display").foregroundStyle(Theme.textMuted)
                Text("\(model.displayName(display)) \(Int((mapped * 100).rounded()))%").foregroundStyle(Theme.solar)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.mono(11, .semibold))
            .foregroundStyle(Theme.textSecondary)
            if !syncing {
                Text(L("Used only in Sync mode")).font(.ui(11)).foregroundStyle(Theme.textFaint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panel()
    }
}

/// Two knobs on one track: the lowest and highest a display goes in Sync.
private struct RangeSlider: View {
    let low: Double
    let high: Double
    let set: (Double, Double) -> Void
    /// The knob being dragged: picked at the start of a drag as the nearer one.
    @State private var draggingLow: Bool?

    var body: some View {
        GeometryReader { geometry in
            let knob: CGFloat = 44
            let travel = geometry.size.width - knob
            ZStack(alignment: .leading) {
                Color.clear.frame(height: 6).recessed(radius: 3)
                Capsule()
                    .fill(Theme.accentGradient)
                    .frame(width: max(travel * (high - low), 0), height: 6)
                    .offset(x: travel * low + knob / 2)
                    .shadow(color: Theme.solar.opacity(0.5), radius: 5)
                knobView(low, title: L("Min")).offset(x: travel * low)
                knobView(high, title: L("Max")).offset(x: travel * high)
            }
            .frame(height: 34)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let f = min(max((drag.location.x - knob / 2) / travel, 0), 1)
                    let value = (f * 100).rounded() / 100
                    let lowSide = draggingLow ?? (abs(value - low) <= abs(value - high) && !(low == high && value > high))
                    draggingLow = lowSide
                    if lowSide { set(min(value, high), high) } else { set(low, max(value, low)) }
                }
                .onEnded { _ in draggingLow = nil })
        }
        .frame(height: 34)
    }

    private func knobView(_ value: Double, title: String) -> some View {
        VStack(spacing: 2) {
            Text("\(Int((value * 100).rounded()))%")
                .font(.mono(10, .bold))
                .foregroundStyle(Theme.solar)
                .frame(width: 44, height: 20)
                .background(Capsule().fill(Theme.island))
                .overlay(Capsule().strokeBorder(Theme.accentGradient, lineWidth: 1.5))
            Text(title.uppercased()).font(.mono(8, .semibold)).foregroundStyle(Theme.textFaint)
        }
        .frame(width: 44)
        .offset(y: 6)
    }
}
