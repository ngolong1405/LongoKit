import LongoKitUI
import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            SettingsGroup(L("Status")) {
                PowerRow(name: AppInfo.name, isOn: model.isEnabled,
                         help: (model.isEnabled ? L("Your keyboards use the keys you set.") : L("Every keyboard types as macOS does by itself."))
                             + " " + L("⌃⌥⌘K turns it on or off from any app.")) {
                    model.isEnabled.toggle()
                }
                // Simple remaps need nothing; only what's missing is listed.
                if !model.hasAccessibility {
                    PermissionLine(L("Accessibility"),
                                   help: L("Until it's granted, Caps Lock set to Hyper stays a normal Caps Lock. In the list, turn on “Longo Keys”."),
                                   granted: false, grant: model.requestAccessibility)
                }
                if !model.hasInputMonitoring {
                    PermissionLine(L("Input Monitoring (optional)"),
                                   help: L("Shows which keyboard you're typing on in the Keyboards tab."),
                                   granted: false, grant: model.requestInputMonitoring)
                }
            }
            AppBehaviorRows(language: $model.language, appearance: $model.appearance, startAtLogin: model.startAtLogin,
                            setStartAtLogin: model.setStartAtLogin, showMenuBarIcon: $model.showMenuBarIcon,
                            menuBarHelp: L("Quick keyboard settings from the menu bar."))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}
