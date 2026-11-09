import LongoKitUI
import SwiftUI

/// Quick controls from the menu bar: mode, a slider per display, presets.
struct MenuPopover: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private let presets: [Double] = [0, 0.25, 0.5, 0.75, 1]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppLogo(size: 32).padding(-2)
                Text(AppInfo.name).font(.display(14, .semibold)).foregroundStyle(Theme.text)
            }
            Segmented(options: BrightnessMode.allCases, selection: $model.mode, title: { $0.title }, stretch: true)
            if model.mode == .sync && !model.externals.isEmpty {
                Text(L("External displays follow the built-in display. Choose Manual to set each one yourself."))
                    .font(.ui(11))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Hairline()

            ForEach(model.displays) { display in
                DisplaySliderRow(display: display)
            }
            if model.displays.isEmpty {
                Text(L("No displays found.")).font(.ui(12)).foregroundStyle(Theme.textMuted)
            }

            HStack(spacing: 6) {
                Text(L("All")).font(.mono(10, .semibold)).foregroundStyle(Theme.textFaint)
                ForEach(presets, id: \.self) { value in
                    Button { model.applyPreset(value) } label: {
                        Text("\(Int(value * 100))%")
                            .font(.mono(11, .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.tint(0.06)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .help(L("Set every display to %d%%", Int(value * 100)))
                }
            }

            Hairline()
            HStack {
                Button(L("Preferences…")) { if !MainWindowRef.show() { openWindow(id: "main") } }
                Spacer()
                Button(L("Quit")) { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.ui(12))
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(width: 320)
        .background(LinearGradient(colors: [Theme.popoverTop, Theme.popoverBottom], startPoint: .top, endPoint: .bottom))
        .id(model.language)
    }
}

private struct DisplaySliderRow: View {
    @EnvironmentObject private var model: AppModel
    let display: Display

    var body: some View {
        let value = model.settings(for: display).brightness
        let on = model.isOn(display)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                    .font(.system(size: 11))
                    .foregroundStyle(on ? Theme.violet : Theme.textFaint)
                Text(model.displayName(display)).font(.ui(12, .medium)).foregroundStyle(on ? Theme.text : Theme.textMuted).lineLimit(1)
                if on {
                    Chip(display.method.title, tone: display.method.tone)
                } else {
                    Chip(L("Off"))
                }
                Spacer()
                PowerButton(display: display)
            }
            if on {
                LevelSlider(symbol: "sun.max.fill", value: value) { model.setBrightness($0, for: display) }
                    .disabled(model.mode == .sync && !display.isBuiltin)
                    .opacity(model.mode == .sync && !display.isBuiltin ? 0.5 : 1)
                    .help(model.mode == .sync && !display.isBuiltin ? L("Follows the built-in display in Sync mode") : L("Brightness"))
                if display.method == .ddc {
                    LevelSlider(symbol: "speaker.wave.2.fill", value: model.volume(for: display)) { model.setVolume($0, for: display) }
                        .help(L("Speaker volume"))
                }
            }
        }
    }
}

/// Turns one display off or back on. The last display that's on can't be turned off.
struct PowerButton: View {
    @EnvironmentObject private var model: AppModel
    let display: Display

    var body: some View {
        let on = model.isOn(display)
        let locked = on && !model.canTurnOff(display)
        Button { model.setPower(display, on: !on) } label: {
            Image(systemName: "power")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(on ? Theme.emerald : Theme.textMuted)
                .frame(width: 22, height: 22)
                .background(Circle().fill(on ? Theme.emerald.opacity(0.14) : Theme.tint(0.06)))
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .opacity(locked ? 0.4 : 1)
        .help(locked ? L("The last display that's on can't be turned off")
              : on ? L("Turn this display off") : L("Turn this display back on"))
    }
}
