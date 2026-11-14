import LongoKitUI
import SwiftUI

/// Where the keyboard and mouse are, and the paired Macs, from the menu bar.
struct MenuPopover: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppLogo(size: 38).padding(-3)
                    .saturation(model.isEnabled ? 1 : 0)
                    .opacity(model.isEnabled ? 1 : 0.75)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppInfo.name).font(.display(14, .semibold)).foregroundStyle(Theme.text)
                    PowerLabel(isOn: model.isEnabled)
                }
                Spacer(minLength: 4)
                ThemeSwitcher(selection: $model.appearance)
                AppPowerButton(name: AppInfo.name, isOn: model.isEnabled) { model.isEnabled.toggle() }
            }
            Hairline()
            VStack(alignment: .leading, spacing: 10) {
                if !model.hasAccessibility {
                    Button(action: model.askForAccessibility) {
                        Label(L("Allow Accessibility to start"), systemImage: "exclamationmark.triangle.fill")
                    }
                    .buttonStyle(GhostButtonStyle(tint: Theme.amber, compact: true))
                }
                StatusPill()
                ForEach(model.paired) { mac in
                    let connected = model.connected.contains(mac.id)
                    HStack(spacing: 10) {
                        Image(systemName: "laptopcomputer").foregroundStyle(connected ? Theme.violetLight : Theme.textFaint).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mac.name).font(.ui(12.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            Text(connected ? L("Connected") : L("Not around now"))
                                .font(.ui(11)).foregroundStyle(Theme.textMuted)
                        }
                        Spacer()
                        Circle().fill(connected ? Theme.emerald : Theme.textFaint).frame(width: 7, height: 7)
                    }
                }
                if model.paired.isEmpty {
                    Text(L("No paired Macs yet. Open Settings to pair one.")).font(.ui(12)).foregroundStyle(Theme.textMuted)
                }
                Text(L("Esc three times brings the mouse back")).font(.ui(11)).foregroundStyle(Theme.textFaint)
            }
            .disabled(!model.isEnabled)
            .opacity(model.isEnabled ? 1 : 0.45)
            Hairline()
            MenuFooter { if !MainWindowRef.show(module: FlowModule.id) { openWindow(id: "main") } }
        }
        .padding(14)
        .popoverFrame(width: 360)
        .id(model.language)
    }
}
