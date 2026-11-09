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
                        Text("\(Int(value * 100))")
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.violet)
                Text(model.displayName(display)).font(.ui(12, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                Chip(display.method.title, tone: display.method.tone)
                Spacer()
                Text("\(Int((value * 100).rounded()))%").font(.mono(11, .semibold)).foregroundStyle(Theme.solar)
            }
            DSSlider(value: Binding(get: { value }, set: { model.setBrightness($0, for: display) }), range: 0...1, step: 0.01)
                .disabled(model.mode == .sync && !display.isBuiltin)
                .opacity(model.mode == .sync && !display.isBuiltin ? 0.5 : 1)
        }
        .help(model.mode == .sync && !display.isBuiltin ? L("Follows the built-in display in Sync mode") : "")
    }
}
