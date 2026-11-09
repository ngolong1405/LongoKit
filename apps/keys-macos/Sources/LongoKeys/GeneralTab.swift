import LongoKitUI
import SwiftUI

struct GeneralTab: View {
    var body: some View {
        VStack(spacing: 12) {
            StatusCard()
            PermissionCard()
            StartupCard()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

/// On / paused, with the way out (⌃⌥⌘K).
private struct StatusCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let on = model.isEnabled
        HStack(spacing: 16) {
            Image(systemName: "power")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(on ? Color.white : Theme.textMuted)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(on ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.slate)))
            VStack(alignment: .leading, spacing: 4) {
                Text(on ? L("%@ is active", AppInfo.name) : L("%@ is paused", AppInfo.name))
                    .font(.display(16, .semibold)).foregroundStyle(Theme.text)
                Text(on ? L("Your keyboards use the keys you set.") : L("Every keyboard types as macOS does by itself."))
                    .font(.ui(12)).foregroundStyle(Theme.textMuted)
                Text(L("⌃⌥⌘K pauses or resumes it from any app.")).font(.ui(11)).foregroundStyle(Theme.textFaint)
            }
            Spacer(minLength: 12)
            DSSwitch(isOn: on) { model.isEnabled.toggle() }
        }
        .panel()
    }
}

/// Simple remaps need nothing; the Hyper key needs Accessibility, and stops inside password fields.
private struct PermissionCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "lock.shield", title: L("Permissions"),
                       subtitle: L("Remapping keys needs no permission. The Hyper key needs Accessibility."),
                       tint: Theme.emerald) {
                Chip(model.hasAccessibility ? L("Granted") : L("Needed for Hyper"), tone: model.hasAccessibility ? .emerald : .amber)
            }
            if !model.hasAccessibility {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
                    Text(L("Until it's granted, Caps Lock set to Hyper stays a normal Caps Lock."))
                        .font(.ui(12)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(L("Grant Access…"), action: model.requestAccessibility).buttonStyle(.primary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.amber.opacity(0.1)))
            }
            Text(L("In password fields macOS turns on Secure Input and hides keys from every app like this one: there the Hyper key waits until you leave the field. Remapped keys keep working."))
                .font(.ui(11)).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
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
                ThemeSwitcher(selection: $model.appearance, large: true)
            }
            Hairline()
            SettingRow(title: L("Start at Login"), detail: L("Launch %@ in the background when your Mac starts up.", AppInfo.name)) {
                DSCheckbox(isOn: model.startAtLogin) { model.setStartAtLogin(!model.startAtLogin) }
            }
            Hairline()
            SettingRow(title: L("Show icon in menu bar"), detail: L("Quick keyboard settings from the menu bar.")) {
                DSCheckbox(isOn: model.showMenuBarIcon) { model.showMenuBarIcon.toggle() }
            }
        }
        .panel()
    }
}
