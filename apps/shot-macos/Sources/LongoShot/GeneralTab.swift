import LongoKitUI
import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            if !model.hasPermission {
                SettingsGroup(L("Permissions")) {
                    PermissionLine(L("Screen Recording"),
                                   help: L("Turn on %@ in System Settings › Privacy & Security › Screen & System Audio Recording. If macOS asks, quit and reopen the app.", AppInfo.name),
                                   granted: false, grant: model.requestPermission)
                }
            }
            CapturesGroup()
            AppBehaviorRows(language: $model.language, appearance: $model.appearance, startAtLogin: model.startAtLogin,
                            setStartAtLogin: model.setStartAtLogin, showMenuBarIcon: $model.showMenuBarIcon,
                            menuBarHelp: menuBarHelp)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var menuBarHelp: String {
        if let shortcut = model.shortcuts[.openSettings] {
            return L("Hidden: press %@ or open %@ again to get back here.", shortcut.symbols, AppInfo.name)
        }
        return L("Hidden: open %@ again to get back here.", AppInfo.name)
    }
}

/// Where captures go and what happens right after one.
private struct CapturesGroup: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsGroup(L("Captures")) {
            CompactRow(L("Save to the folder"),
                       help: model.saveToFolder ? L("On: each capture is saved as a PNG file named with its date and time, and copied.")
                                                : L("Off: captures only go to the clipboard, ready to paste. Nothing is saved.")) {
                DSSwitch(isOn: $model.saveToFolder)
            }
            if model.saveToFolder {
                HStack(spacing: 8) {
                    Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                    Text(displayPath(model.saveFolder))
                        .font(.mono(12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.saveFolder.path)
                    Spacer(minLength: 8)
                    Button(L("Change…"), action: model.chooseFolder).buttonStyle(GhostButtonStyle(compact: true))
                    Button { model.perform(.openFolder) } label: { Image(systemName: "arrow.up.forward.app") }
                        .buttonStyle(GhostButtonStyle(compact: true))
                        .help(L("Show in Finder"))
                }
                .settingsRow(minHeight: 40)
            }
            // Without saving, the clipboard is the only place a capture goes, so it stays on.
            CompactRow(L("Copy to the clipboard"),
                       help: model.saveToFolder ? nil : L("Always on while captures aren't saved.")) {
                DSSwitch(isOn: model.copyToClipboard || !model.saveToFolder) { model.copyToClipboard.toggle() }
                    .disabled(!model.saveToFolder)
                    .opacity(model.saveToFolder ? 1 : 0.5)
            }
            CompactRow(L("Show a preview"),
                       help: L("A thumbnail in the corner to drag into another app, copy, or show in Finder.")) {
                DSSwitch(isOn: $model.showPreview)
            }
            CompactRow(L("Play the capture sound")) {
                DSSwitch(isOn: $model.playSound)
            }
        }
    }

    /// "~/Downloads" for folders in the home folder.
    private func displayPath(_ url: URL) -> String {
        let home = NSHomeDirectory()
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}
