import LongoKitUI
import SwiftUI

struct GeneralTab: View {
    var body: some View {
        VStack(spacing: 12) {
            ModeCard()
            KeysCard()
            StartupCard()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

/// Manual or Sync, with what Sync does in one line.
private struct ModeCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(symbol: "sun.max.fill", title: L("Brightness Mode"),
                       subtitle: L("How external displays get their brightness."), tint: Theme.solar) {
                Segmented(options: BrightnessMode.allCases, selection: $model.mode, title: { $0.title })
            }
            Text(model.mode == .sync
                 ? (model.builtin == nil
                    ? L("Sync needs a built-in display. On this Mac, external displays keep their own brightness.")
                    : L("External displays follow the built-in display, each within its own Sync range (set on its page)."))
                 : L("Each display keeps the brightness you set."))
                .font(.ui(12))
                .foregroundStyle(Theme.textMuted)
        }
        .panel()
    }
}

/// Brightness keys for external displays, and the permission they need.
private struct KeysCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(symbol: "keyboard", title: L("Brightness Keys"),
                       subtitle: L("Point at an external display and press the brightness keys to change that display."),
                       tint: Theme.violet) {
                DSSwitch(isOn: $model.keysEnabled)
            }
            if model.keysEnabled && !model.hasAccessibility {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
                    Text(L("Needs Accessibility permission to catch the brightness keys."))
                        .font(.ui(12))
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    Button(L("Grant Access…"), action: model.requestAccessibility).buttonStyle(.primary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.amber.opacity(0.1)))
            } else {
                Text(model.keysEnabled ? L("On: with the pointer on an external display, the brightness keys change that display and show its level. On the MacBook screen they work as usual.")
                                      : L("Off: the brightness keys only change the MacBook screen, as macOS does by itself."))
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.ui(12))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .panel()
    }
}

private struct StartupCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "gearshape.fill", title: L("Startup & Behavior"),
                       subtitle: L("Language, look, and how %@ starts.", AppInfo.name)) { EmptyView() }
            SettingRow(title: L("Language"), detail: L("Language used throughout the app.")) {
                Segmented(options: AppLanguage.allCases, selection: $model.language, title: { $0.title })
            }
            Hairline()
            SettingRow(title: L("Appearance"), detail: L("Follow macOS, or always use dark or light.")) {
                Segmented(options: AppAppearance.allCases, selection: $model.appearance, title: { $0.title })
            }
            Hairline()
            SettingRow(title: L("Start at Login"), detail: L("Launch %@ in the background when your Mac starts up.", AppInfo.name)) {
                DSCheckbox(isOn: model.startAtLogin) { model.setStartAtLogin(!model.startAtLogin) }
            }
            Hairline()
            SettingRow(title: L("Show icon in menu bar"), detail: L("Quick brightness controls from the menu bar.")) {
                DSCheckbox(isOn: model.showMenuBarIcon) { model.showMenuBarIcon.toggle() }
            }
        }
        .panel()
    }
}
