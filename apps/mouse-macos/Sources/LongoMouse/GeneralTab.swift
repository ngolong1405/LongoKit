import LongoKitUI
import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            StatusCard()
            // Missing permissions come first; once everything is granted the everyday settings move up.
            if model.allPermissionsGranted {
                StartupCard()
                PermissionsCard()
            } else {
                PermissionsCard()
                StartupCard().opacity(0.8)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

/// On/off for remapping, and what's in effect right now. The window title already names the app.
private struct StatusCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let running = model.isRunning
        HStack(spacing: 14) {
            Image(systemName: "power")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(running ? Color.white : Theme.textMuted)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(running ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.slate))
                )
                .shadow(color: Theme.solar.opacity(running ? 0.4 : 0), radius: 8)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(running ? L("%@ is active", AppInfo.name) : L("%@ is paused", AppInfo.name))
                        .font(.display(16, .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Theme.text)
                    if !model.hasAccessibility { Chip(L("Action Required"), tone: .amber) }
                }
                Text(subtitle)
                    .font(.ui(12))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if model.hasAccessibility {
                    Text(L("⌃⌥⌘M pauses or resumes it from any app."))
                        .font(.ui(11))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            Spacer(minLength: 12)
            DSSwitch(isOn: running) { model.toggleEnabled() }
        }
        .panel()
        .shadow(color: Theme.solar.opacity(running ? 0.12 : 0), radius: 18)
    }

    private var subtitle: String {
        if model.isRelaunching { return L("All permissions granted. Restarting %@ to finish setting up…", AppInfo.name) }
        if !model.hasAccessibility {
            return L("Mouse click capture, gestures, and scrolling are suspended until permissions are granted.")
        }
        guard model.isRunning else { return L("%@ is paused. Flip the switch to turn it back on.", AppInfo.name) }
        guard let device = model.activeDevice else { return L("No mouse connected yet.") }
        let buttons = model.activeProfileDeviceID != nil ? L("Own buttons") : L("Shared buttons")
        let scrolling = model.activeScrollDeviceID != nil ? L("Own scrolling") : L("Shared scrolling")
        return L("In use: %@", model.displayName(device.id)) + " · " + buttons + " · " + scrolling
    }
}

private struct PermissionsCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let ok = model.allPermissionsGranted
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(symbol: ok ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                       title: L("Accessibility & Permissions"),
                       subtitle: L("What macOS must allow for %@ to work.", AppInfo.name),
                       tint: ok ? Theme.emerald : Theme.amber) {
                ok ? Chip(L("All Granted"), tone: .emerald) : Chip(L("Permission Required"), tone: .amber)
            }

            if !ok { warning }

            VStack(spacing: 12) {
                PermissionRow(
                    title: L("Accessibility Access"),
                    granted: model.hasAccessibility,
                    description: model.hasAccessibility
                        ? L("Lets %@ remap mouse buttons and gestures. If disabled, overrides are paused.", AppInfo.name)
                        : L("Required for mouse button reconfiguration and gesture processing. Currently blocked by macOS."),
                    action: model.requestAccessibility)
                Hairline()
                PermissionRow(
                    title: L("Input Monitoring"),
                    granted: model.hasInputMonitoring,
                    description: L("Recognizes hardware side buttons and scroll events across all applications."),
                    action: model.requestInputMonitoring)
            }
            .padding(.top, 2)

            settingsBox(ok)
        }
        .panel()
    }

    private var warning: some View {
        let bright = Color.dynamic(dark: 0xFEF3C7, light: 0x78350F)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .padding(.top, 1)
            (Text(L("macOS requires "))
                + Text(L("Accessibility")).bold().foregroundColor(bright)
                + Text(L(" and "))
                + Text(L("Input Monitoring")).bold().foregroundColor(bright)
                + Text(L(" to intercept hardware buttons, remap gestures, and reshape scrolling.")))
                .font(.ui(12))
                .foregroundStyle(Color.dynamic(dark: 0xFCD34D, light: 0x92400E, darkOpacity: 0.85))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.amber.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.amber.opacity(0.25)))
    }

    private func settingsBox(_ ok: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(Theme.violet)
            Text(L("Privacy & Security › Accessibility"))
                .font(.ui(12))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            if ok {
                Button(action: model.openAccessibilitySettings) {
                    Label(L("Open System Settings…"), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.ghost)
            } else {
                Button(action: model.refreshPermissions) {
                    Label(L("Re-check"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.ghost)
                Button(action: model.grantNextPermission) {
                    Label(L("Grant Permission…"), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.primary)
            }
        }
        .padding(10)
        .recessed(radius: 10)
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let description: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(granted ? Theme.emerald : Theme.amber)
                    Text(title).font(.ui(13)).foregroundStyle(Theme.text)
                    if !granted { Chip(L("Not Granted"), tone: .amber) }
                }
                Text(description)
                    .font(.ui(11))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            DSSwitch(isOn: granted, action: action)
        }
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
            SettingRow(title: L("Start at Login"),
                       detail: L("Launch %@ in the background when your Mac starts up.", AppInfo.name)) {
                DSCheckbox(isOn: model.startAtLogin) { model.setStartAtLogin(!model.startAtLogin) }
            }
            Hairline()
            SettingRow(title: L("Show icon in menu bar"), detail: L("Quick access to enable/disable and settings.")) {
                DSCheckbox(isOn: model.showMenuBarIcon) { model.showMenuBarIcon.toggle() }
            }
            Hairline()
            SettingRow(title: L("Check for updates automatically"),
                       detail: L("Notify when new versions with enhancements and fixes are released."), soon: true) {
                DSCheckbox(isOn: model.autoCheckUpdates) { model.autoCheckUpdates.toggle() }
            }
        }
        .panel()
    }
}
