import LongoKitUI
import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            SettingsGroup(L("Brightness")) {
                CompactRow(L("Brightness Mode"), help: modeHelp) {
                    Segmented(options: BrightnessMode.allCases, selection: $model.mode, title: { $0.title })
                }
                CompactRow(L("Brightness Keys"),
                           help: model.keysEnabled ? L("On: with the pointer on an external display, the brightness keys change that display and show its level. On the MacBook screen they work as usual.")
                                                   : L("Off: the brightness keys only change the MacBook screen, as macOS does by itself.")) {
                    DSSwitch(isOn: $model.keysEnabled)
                }
                if model.keysEnabled && !model.hasAccessibility {
                    PermissionLine(L("Accessibility"), help: L("Needs Accessibility permission to catch the brightness keys."),
                                   granted: false, grant: model.requestAccessibility)
                }
            }
            AppBehaviorRows(language: $model.language, appearance: $model.appearance, startAtLogin: model.startAtLogin,
                            setStartAtLogin: model.setStartAtLogin, showMenuBarIcon: $model.showMenuBarIcon,
                            menuBarHelp: L("Quick brightness controls from the menu bar."))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var modeHelp: String {
        guard model.mode == .sync else { return L("Each display keeps the brightness you set.") }
        return model.builtin == nil
            ? L("Sync needs a built-in display. On this Mac, external displays keep their own brightness.")
            : L("External displays follow the built-in display, each within its own Sync range (set on its page).")
    }
}
