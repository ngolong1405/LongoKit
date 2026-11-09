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

            PowerCard(display: display)
            if display.hasDDC && model.isOn(display) {
                ControlCard(display: display)
            }

            Group {
            HStack(alignment: .center, spacing: 20) {
                LimitTile(title: L("Min brightness"), value: value.minimum) { new in
                    model.update(display) { $0.minimum = min(new, $0.maximum) }
                }
                ScreenCard(display: display, value: value)
                LimitTile(title: L("Max brightness"), value: value.maximum) { new in
                    model.update(display) { $0.maximum = max(new, $0.minimum) }
                }
            }
            Text(L("In Sync mode this display moves between its minimum and maximum as the built-in display changes."))
                .font(.ui(11))
                .foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity)
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

/// Hardware (DDC) or software dimming, for monitors that have DDC.
private struct ControlCard: View {
    @EnvironmentObject private var model: AppModel
    let display: Display

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "slider.horizontal.3", title: L("Brightness Control"),
                       subtitle: L("Hardware changes the monitor's backlight; Software darkens the picture."),
                       tint: Theme.violet, divider: model.isDDCSilent(display)) {
                Segmented(options: ControlChoice.allCases,
                          selection: Binding(get: { model.settings(for: display).control },
                                             set: { model.setControl(display, $0) }),
                          title: \.title)
            }
            if model.isDDCSilent(display) {
                Text(L("This monitor takes DDC commands but doesn't report its brightness back (common on a MacBook's HDMI port), so the app can't read where it starts. If moving the slider doesn't change it, choose Software."))
                    .font(.ui(11))
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .panel()
    }
}

/// On / off for this display, with the way back spelled out.
private struct PowerCard: View {
    @EnvironmentObject private var model: AppModel
    let display: Display

    var body: some View {
        let on = model.isOn(display)
        let locked = on && !model.canTurnOff(display)
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "power", title: L("Display Power"),
                       subtitle: L("Off works like unplugging it: windows move to your other displays."),
                       tint: on ? Theme.emerald : Theme.slate) {
                DSSwitch(isOn: on) { model.setPower(display, on: !on) }
                    .disabled(locked)
                    .opacity(locked ? 0.4 : 1)
            }
            Text(locked ? L("The last display that's on can't be turned off")
                 : L("You'll be asked to keep it off; with no answer it turns back on in %d seconds. ⌃⌥⌘B turns every display back on at any time.", PowerConfirmation.seconds))
                .font(.ui(11))
                .foregroundStyle(Theme.textMuted)
        }
        .panel()
    }
}

private struct ScreenCard: View {
    @EnvironmentObject private var model: AppModel
    let display: Display
    let value: DisplaySettings

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(model.displayName(display))
                    .font(.display(24, .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Chip(display.method.title, tone: display.method.tone, dot: true)
                BrightnessLevel(display: display)
                    // In Sync an external display follows the built-in one, as in the menu.
                    .disabled(model.mode == .sync && !display.isBuiltin)
                    .opacity(model.mode == .sync && !display.isBuiltin ? 0.5 : 1)
                    .help(model.mode == .sync && !display.isBuiltin ? L("Follows the built-in display in Sync mode") : "")
                    .padding(.top, 6)
                if display.method == .ddc {
                    VolumeSlider(value: model.volume(for: display), help: L("Speaker volume")) { model.setVolume($0, for: display) }
                } else if display.isBuiltin, let volume = model.systemVolume {
                    VolumeSlider(value: volume, help: L("Mac volume")) { model.setSystemVolume($0) }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.well))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderProminent, lineWidth: 6))
            // Stand
            Rectangle().fill(Theme.slate).frame(width: 60, height: 18)
            RoundedRectangle(cornerRadius: 3).fill(Theme.slate).frame(width: 130, height: 6)
            Text(display.sizeLabel)
                .font(.mono(11))
                .foregroundStyle(Theme.textMuted)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }
}

/// MIN / MAX: a big number with a small slider underneath.
private struct LimitTile: View {
    let title: String
    let value: Double
    let set: (Double) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("\(Int((value * 100).rounded()))")
                .font(.display(40, .bold))
                .foregroundStyle(Theme.solar)
                .frame(width: 120, height: 70)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.island))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
            Text(title.uppercased()).font(.mono(10, .semibold)).foregroundStyle(Theme.textMuted)
            DSSlider(value: Binding(get: { value }, set: set), range: 0...1, step: 0.01)
                .frame(width: 120)
        }
    }
}
