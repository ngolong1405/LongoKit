import LongoKitUI
import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            // Missing permissions come first; once everything is granted they're no longer listed.
            if !model.allPermissionsGranted {
                SettingsGroup(L("Permissions")) {
                    PermissionLine(L("Accessibility"),
                                   help: L("Required for mouse button reconfiguration and gesture processing. Currently blocked by macOS."),
                                   granted: model.hasAccessibility, grant: model.requestAccessibility)
                    PermissionLine(L("Input Monitoring"),
                                   help: L("Recognizes hardware side buttons and scroll events across all applications."),
                                   granted: model.hasInputMonitoring, grant: model.requestInputMonitoring)
                }
            }
            SettingsGroup(L("Mouse")) {
                StatusRow()
                ClickFixRows()
            }
            AppBehaviorRows(language: $model.language, appearance: $model.appearance, startAtLogin: model.startAtLogin,
                            setStartAtLogin: model.setStartAtLogin, showMenuBarIcon: $model.showMenuBarIcon,
                            menuBarHelp: L("Quick access to enable/disable and settings."))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

/// On/off for remapping, the same switch as in the menu; what's in effect right now is in the tooltip.
private struct StatusRow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        PowerRow(name: AppInfo.name, isOn: model.isEnabled, help: help,
                 attention: model.hasAccessibility ? nil : L("Action Required"), toggle: model.toggleEnabled)
    }

    private var help: String {
        if model.isRelaunching { return L("All permissions granted. Restarting %@ to finish setting up…", AppInfo.name) }
        if !model.hasAccessibility {
            return L("Mouse click capture, gestures, and scrolling are suspended until permissions are granted.")
        }
        let shortcut = L("⌃⌥⌘M turns it on or off from any app.")
        guard model.isRunning else { return L("Off: mouse buttons and scrolling work as macOS does by itself.") + " " + shortcut }
        guard let device = model.activeDevice else { return L("No mouse connected yet.") + " " + shortcut }
        let buttons = model.activeProfileDeviceID != nil ? L("Own buttons") : L("Shared buttons")
        let scrolling = model.activeScrollDeviceID != nil ? L("Own scrolling") : L("Shared scrolling")
        return L("In use: %@", model.displayName(device.id)) + " · " + buttons + " · " + scrolling + "\n" + shortcut
    }
}

/// For a worn left/right button that sometimes clicks twice: presses that bounce closer than the threshold count once.
private struct ClickFixRows: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        CompactRow(L("Double-Click Fix"), help: L("For a worn button that sometimes clicks twice when pressed once.")) {
            DSSwitch(isOn: model.clickGuardOn) { model.clickGuardOn.toggle() }
        }
        if model.clickGuardOn {
            HStack(spacing: 12) {
                Text(L("Ignore a second click within")).font(.ui(12)).foregroundStyle(Theme.textSecondary)
                InfoTip(L("Left and right buttons. A real double click is slower than this, so it still works; raise it if the button still double-clicks, lower it if your own fast double clicks stop working."))
                DSSlider(value: $model.clickGuardMs, range: AppModel.clickGuardRange, step: 5,
                         label: "\(Int(model.clickGuardMs)) ms")
            }
            .settingsRow()
        }
    }
}
