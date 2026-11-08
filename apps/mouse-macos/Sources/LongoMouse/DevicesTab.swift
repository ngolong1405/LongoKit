import SwiftUI

/// Mice the app knows about. Picking one (or "All mice") opens its settings page with Buttons and Scrolling.
struct DevicesTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.showingDeviceDetail {
                DeviceDetail()
            } else {
                DeviceList()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

// MARK: - List

private struct DeviceList: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SharedRow()
                .panel(padding: 0)

            HStack {
                SectionLabel(text: L("Connected mice") + " (\(model.connectedDevices.count))")
                Spacer()
                Button(action: model.refreshDevices) { Label(L("Refresh"), systemImage: "arrow.clockwise") }
                    .buttonStyle(.ghost)
                Button(action: model.openBluetoothSettings) { Label(L("Pair a mouse…"), systemImage: "plus") }
                    .buttonStyle(.ghost)
            }

            if model.connectedDevices.isEmpty {
                Text(L("No mouse detected. Connect one over Bluetooth or USB, and make sure Input Monitoring is granted on the General tab."))
                    .font(.ui(12))
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.connectedDevices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 { Hairline() }
                        DeviceRow(device: device)
                    }
                }
                .panel(padding: 0)
            }

            if !model.offlineDeviceIDs.isEmpty {
                SectionLabel(text: L("Remembered, not connected"))
                VStack(spacing: 0) {
                    ForEach(Array(model.offlineDeviceIDs.enumerated()), id: \.element) { index, id in
                        if index > 0 { Hairline() }
                        OfflineRow(id: id)
                    }
                }
                .panel(padding: 0)
            }

            SettingRow(title: L("Switch profile automatically"),
                       detail: L("Use the settings of whichever mouse you're touching.")) {
                DSSwitch(isOn: $model.autoSwitchProfiles)
            }
            .panel()
        }
        .animation(Motion.list, value: model.connectedDevices.map(\.id))
        .animation(Motion.list, value: model.offlineDeviceIDs)
    }
}

/// "All mice": the shared settings every mouse without its own uses.
private struct SharedRow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.violet)
                .frame(width: 38, height: 38)
                .recessed(radius: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("All mice")).font(.display(14, .semibold)).foregroundStyle(Theme.text)
                Text(L("Shared settings, used by every mouse without its own")).font(.ui(11)).foregroundStyle(Theme.textMuted)
            }
            Spacer()
            OpenButton { model.open(nil) }
        }
        .padding(14)
    }
}

private struct DeviceRow: View {
    @EnvironmentObject private var model: AppModel
    let device: MouseDevice

    var body: some View {
        let inUse = model.activeDevice?.id == device.id
        HStack(spacing: 12) {
            Image(systemName: device.symbol)
                .font(.system(size: 16))
                .foregroundStyle(Theme.violetLight)
                .frame(width: 38, height: 38)
                .recessed(radius: 10)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    InlineRename(deviceID: device.id)
                    if inUse { Chip(L("In use"), tone: .emerald, dot: true) }
                }
                Text(details).font(.ui(11)).foregroundStyle(Theme.textMuted)
            }
            Spacer()
            OwnBadges(id: device.id)
            OpenButton { model.open(device.id) }
        }
        .padding(14)
    }

    private var details: String {
        var parts = [device.manufacturer.isEmpty ? device.product : "\(device.manufacturer) \(device.product)", device.connection]
        if let battery = device.battery { parts.append("\(battery)% " + L("battery")) }
        return parts.joined(separator: " · ")
    }
}

/// Which of a mouse's settings are its own rather than shared.
private struct OwnBadges: View {
    @EnvironmentObject private var model: AppModel
    let id: String

    var body: some View {
        let profile = model.profiles[id]
        HStack(spacing: 4) {
            if profile?.independent == true { Chip(L("Own buttons"), tone: .solar) }
            if profile?.scroll != nil { Chip(L("Own scrolling"), tone: .violet) }
            if profile?.independent != true && profile?.scroll == nil {
                Text(L("Shared settings")).font(.ui(10)).foregroundStyle(Theme.textFaint)
            }
        }
    }
}

private struct OpenButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(L("Customize"))
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
            }
        }
        .buttonStyle(.ghost)
    }
}

// MARK: - Settings page

/// One mouse (or all of them): its name up top, then Buttons or Scrolling.
private struct DeviceDetail: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch model.deviceSection {
            case .buttons: ButtonsPane()
            case .scrolling: ScrollingPane()
            }
        }
    }

    private var header: some View {
        let id = model.editingDeviceID
        let device = model.connectedDevices.first { $0.id == id }
        return VStack(alignment: .leading, spacing: 12) {
            Button { model.showingDeviceDetail = false } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                    Text(L("Devices"))
                }
                .font(.ui(12, .medium))
                .foregroundStyle(Theme.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Back to the list of mice"))

            HStack(spacing: 14) {
                GlyphTile(tint: id == nil ? Theme.violet : Theme.solar, size: 44) {
                    Image(systemName: id == nil ? "square.stack.3d.up.fill" : device?.symbol ?? "computermouse")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(id == nil ? Theme.violet : Theme.solar)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        if let id {
                            InlineRename(deviceID: id, font: .display(19, .semibold))
                        } else {
                            Text(L("All mice")).font(.display(19, .semibold)).foregroundStyle(Theme.text)
                        }
                        if let id, id == model.activeDevice?.id {
                            Chip(L("In use"), tone: .emerald, dot: true)
                        }
                    }
                    Text(subtitle(id, device))
                        .font(.ui(12))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                Segmented(options: DeviceSection.allCases, selection: $model.deviceSection, title: { $0.title })
            }
        }
    }

    private func subtitle(_ id: String?, _ device: MouseDevice?) -> String {
        guard let id else { return L("Shared settings, used by every mouse without its own") }
        let profile = model.profiles[id]
        let hardware = [profile?.manufacturer, profile?.product].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let connection = device.map { d in [d.connection] + (d.battery.map { ["\($0)% " + L("battery")] } ?? []) }
            ?? [L("Not connected")]
        return ([hardware] + connection).filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

private struct OfflineRow: View {
    @EnvironmentObject private var model: AppModel
    let id: String

    static let relative = RelativeDateTimeFormatter()

    var body: some View {
        let profile = model.profiles[id]
        HStack(spacing: 12) {
            Image(systemName: MouseDevice.symbol(for: profile?.product ?? ""))
                .font(.system(size: 14))
                .foregroundStyle(Theme.textFaint)
                .frame(width: 32, height: 32)
                .recessed(radius: 9)
            VStack(alignment: .leading, spacing: 2) {
                InlineRename(deviceID: id, font: .display(13, .semibold), color: Theme.textSecondary)
                Text(L("Last seen") + " " + (profile.map { OfflineRow.relative.localizedString(for: $0.lastSeen, relativeTo: Date()) } ?? "—"))
                    .font(.ui(11))
                    .foregroundStyle(Theme.textFaint)
            }
            Spacer()
            Button(L("Forget")) { model.forget(id) }
                .buttonStyle(GhostButtonStyle(tint: Theme.solarLight))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
