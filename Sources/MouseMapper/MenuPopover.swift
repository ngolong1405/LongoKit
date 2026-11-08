import SwiftUI

/// Quick controls shown from the menu bar icon: on/off, theme, scrolling, and which mice use their own buttons.
struct MenuPopover: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Hairline()
            scrolling
            Hairline()
            mice
            Hairline()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .background(
            LinearGradient(colors: [Theme.popoverTop, Theme.popoverBottom], startPoint: .top, endPoint: .bottom)
        )
        .id(model.language)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            AppLogo(size: 38, dimmed: !model.isRunning).padding(-3)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppInfo.name).font(.display(14, .semibold)).foregroundStyle(Theme.text)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6).shadow(color: statusColor, radius: 3)
                    Text(statusText).font(.ui(11)).foregroundStyle(statusColor).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            ThemeSwitcher()
            Button(action: model.toggleEnabled) {
                Image(systemName: "power").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(model.isRunning ? Color.white : Theme.textMuted)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(model.isRunning ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.slate))
                    )
                    .shadow(color: Theme.solar.opacity(model.isRunning ? 0.45 : 0), radius: 6)
            }
            .buttonStyle(.plain)
            .help(model.isRunning ? L("Pause %@", AppInfo.name) : L("Turn %@ back on", AppInfo.name))
        }
    }

    private var scrolling: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                SectionLabel(text: L("Scrolling"))
                Text(model.activeScrollDeviceID.map { model.displayName($0) } ?? L("All mice"))
                    .font(.ui(11, .semibold))
                    .foregroundStyle(Theme.solar)
                    .lineLimit(1)
                Spacer()
            }
            .help(L("Changes here apply to this mouse's scroll settings"))
            HStack {
                Text(L("Scroll Direction")).font(.ui(12)).foregroundStyle(Theme.text)
                Spacer()
                Segmented(options: [false, true], selection: $model.inUseScroll.invertDirection,
                          title: { $0 ? L("Classic") : L("Natural") })
            }
            HStack {
                Text(L("Smooth Scrolling")).font(.ui(12)).foregroundStyle(Theme.text)
                Spacer()
                QuickSwitch(isOn: model.inUseScroll.inertia) { model.inUseScroll.inertia.toggle() }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Custom Scroll Speed")).font(.ui(12)).foregroundStyle(Theme.text)
                        Text(L("Hold ⌥ to slow down, ⌘ to speed up")).font(.ui(10)).foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    if model.inUseScroll.smoothEnabled {
                        Text(String(format: "%.2f×", model.inUseScroll.speed)).font(.mono(11, .semibold)).foregroundStyle(Theme.solar)
                    }
                    QuickSwitch(isOn: model.inUseScroll.smoothEnabled) { model.inUseScroll.smoothEnabled.toggle() }
                }
                DSSlider(value: $model.inUseScroll.speed, range: ScrollSettings.speedRange, step: 0.05)
                    .opacity(model.inUseScroll.smoothEnabled ? 1 : 0.4)
                    .disabled(!model.inUseScroll.smoothEnabled)
            }
        }
    }

    private var mice: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: L("Connected mice"))
            if model.connectedDevices.isEmpty {
                Text(L("No mouse detected. Connect one over Bluetooth or USB."))
                    .font(.ui(11))
                    .foregroundStyle(Theme.textMuted)
            }
            ForEach(model.connectedDevices) { device in
                mouseRow(device)
            }
        }
    }

    private func mouseRow(_ device: MouseDevice) -> some View {
        let separate = model.profiles[device.id]?.independent ?? false
        let active = device.id == model.activeDevice?.id
        return HStack(spacing: 8) {
            Circle().fill(active ? Theme.emerald : Theme.textFaint).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName(device.id)).font(.ui(12, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                Text((separate ? L("Own buttons") : L("Shared buttons")) + " · " + device.connection
                     + (device.battery.map { " · \($0)%" } ?? ""))
                    .font(.ui(10))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { openMain(device.id) } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.tint(0.06)))
            }
            .buttonStyle(.plain)
            .help(L("Open this mouse's settings"))
            QuickSwitch(isOn: separate) { model.setIndependent(device.id, !separate) }
                .help(separate ? L("Switch back to the shared buttons") : L("Give this mouse its own buttons"))
        }
    }

    private var footer: some View {
        HStack {
            Button(L("Preferences…")) { openMain(nil) }
            Spacer()
            Button(L("Quit")) { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .font(.ui(12))
        .foregroundStyle(Theme.textSecondary)
    }

    // MARK: Helpers

    private var statusText: String {
        if !model.hasAccessibility { return L("Paused · Needs Accessibility") }
        return model.isRunning ? L("Running") : L("Paused")
    }

    private var statusColor: Color {
        model.isRunning ? Theme.emerald : Theme.amber
    }

    /// Brings up the main window, optionally on a mouse's button configuration.
    private func openMain(_ deviceID: String?) {
        if let deviceID { model.configure(deviceID) }
        if let window = MainWindowRef.window {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// A DSSwitch scaled down to fit popover rows.
private struct QuickSwitch: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        DSSwitch(isOn: isOn, action: action)
            .scaleEffect(0.8)
            .frame(width: 32, height: 18)
    }
}
