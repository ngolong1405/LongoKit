import LongoKitUI
import SwiftUI

/// Devices nearby from the menu bar: click one to pick files for it, or send it some text.
struct MenuPopover: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    /// Logo, name and status; theme; pause, like the other apps' menus.
    private var header: some View {
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
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Hairline()
            VStack(alignment: .leading, spacing: 10) {
                ProblemBanner()
                ActivityView()
                HStack {
                    Text(model.isScanning ? L("Looking for devices…") : L("Nearby"))
                        .font(.ui(12, .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    IconButton(symbol: "plus", help: L("Add by address")) { Panels.addByAddress(model: model) }
                    IconButton(symbol: "arrow.clockwise", help: L("Look Again")) { Task { await model.refresh() } }
                }
                ForEach(model.peers) { peer in PeerRow(peer: peer, compact: true) }
                if model.peers.isEmpty {
                    EmptyDevices()
                } else {
                    Text(L("Click a device to pick files for it. To drop files, use the window."))
                        .font(.ui(11))
                        .foregroundStyle(Theme.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Hairline()
                HStack {
                    Text(L("This Mac: %@", model.alias)).font(.ui(11.5)).foregroundStyle(Theme.textMuted).lineLimit(1)
                    Spacer()
                    IconButton(symbol: "folder", help: L("Open Received Files")) { NSWorkspace.shared.open(model.folder) }
                }
            }
            .disabled(!model.isEnabled)
            .opacity(model.isEnabled ? 1 : 0.45)

            Hairline()
            MenuFooter { if !MainWindowRef.show(module: ShareModule.id) { openWindow(id: "main") } }
        }
        .padding(14)
        .popoverFrame(width: 380)
        .id(model.language)
    }
}
