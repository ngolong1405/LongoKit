import LongoKitUI
import SwiftUI

/// Devices nearby from the menu bar: click one to open its chat, or send it files straight away.
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
            VStack(alignment: .leading, spacing: 8) {
                ProblemBanner()
                if let transfer = model.current {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(transfer.sending ? L("Sending to %@", transfer.device) : L("Receiving from %@", transfer.device))
                            .font(.ui(12, .semibold)).foregroundStyle(Theme.text)
                        ProgressBar(fraction: transfer.fraction)
                    }
                    .panel(padding: 10)
                }
                HStack {
                    Text(model.isScanning ? L("Looking for devices…") : L("Nearby"))
                        .font(.ui(12, .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    IconButton(symbol: "arrow.clockwise", help: L("Look Again")) { Task { await model.refresh() } }
                }
                ForEach(model.contacts.filter { $0.isOnline || ($0.conversation?.unread ?? 0) > 0 }) { contact in
                    MenuDeviceRow(contact: contact) { openChat(contact.id) }
                }
                if model.peers.isEmpty { EmptyDevices() }
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
            MenuFooter { showWindow() }
        }
        .padding(14)
        .popoverFrame(width: 380)
        .id(model.language)
    }

    private func openChat(_ id: String) {
        model.tab = .devices
        model.selected = id
        showWindow()
    }

    private func showWindow() {
        if !MainWindowRef.show(module: ShareModule.id) { openWindow(id: "main") }
    }
}

private struct MenuDeviceRow: View {
    @EnvironmentObject private var model: AppModel
    let contact: Contact
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            DeviceBadge(info: contact.info, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.info.alias).font(.ui(12.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(contact.conversation?.items.last.map(Preview.line) ?? contact.info.deviceModel ?? "")
                    .font(.ui(11)).foregroundStyle(Theme.textMuted).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let unread = contact.conversation?.unread, unread > 0 {
                Text("\(unread)").font(.mono(10, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(Theme.solar))
            }
            if let peer = contact.peer {
                IconButton(symbol: "paperclip", help: L("Send files")) { pickFiles(peer) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovered ? Theme.hover : Theme.tint(0.04)))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: open)
        .help(L("Open the chat"))
    }

    private func pickFiles(_ peer: Peer) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = L("Send")
        panel.message = L("Send to %@", peer.info.alias)
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { model.send(panel.urls, to: peer) }
    }
}
