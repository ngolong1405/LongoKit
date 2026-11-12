import LongoKitUI
import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            SettingsGroup(L("Status")) {
                PowerRow(name: AppInfo.name, isOn: model.isEnabled,
                         help: model.isEnabled ? L("Your shortcuts capture and record from any app.")
                             : L("Off: the shortcuts let go, so other apps can use them; the menu still captures.")) {
                    model.isEnabled.toggle()
                }
                if !model.hasPermission {
                    PermissionLine(L("Screen Recording"),
                                   help: L("Turn on %@ in System Settings › Privacy & Security › Screen & System Audio Recording. If macOS asks, quit and reopen the app.", AppInfo.name),
                                   granted: false, grant: model.requestPermission)
                }
            }
            CapturesGroup()
            RecordingGroup()
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
            // Saving, with the folder right under it while it's on.
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(L("Save to the folder")).font(.ui(13, .medium)).foregroundStyle(Theme.text)
                    InfoTip(model.saveToFolder ? L("On: each capture is saved as a PNG file named with its date and time, and copied.")
                                               : L("Off: captures only go to the clipboard, ready to paste. Nothing is saved."))
                    Spacer(minLength: 12)
                    DSSwitch(isOn: $model.saveToFolder)
                }
                if model.saveToFolder {
                    HStack(spacing: 8) {
                        Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Theme.solar)
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
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .recessed()
                }
            }
            .padding(.vertical, 12)
            .settingsRow()

            ChipsRow(L("After a capture")) {
                // Without saving, the clipboard is the only place a capture goes, so it stays on.
                CheckChip(L("Copy to the clipboard"), isOn: model.copyToClipboard || !model.saveToFolder,
                          help: model.saveToFolder ? L("Paste the capture straight into a chat, a document or Finder.")
                                                   : L("Always on while captures aren't saved.")) {
                    model.copyToClipboard.toggle()
                }
                .disabled(!model.saveToFolder)
                CheckChip(L("Draw on it"), isOn: model.drawAfterCapture,
                          help: L("An area, a window or the whole screen stays put with arrows, pen, boxes and colors; Done or ⌘C saves and copies it, Esc goes back to picking the area.")) {
                    model.drawAfterCapture.toggle()
                }
                CheckChip(L("Preview"), isOn: model.showPreview,
                          help: L("A thumbnail in the corner to drag into another app, copy, or show in Finder.")) {
                    model.showPreview.toggle()
                }
                CheckChip(L("Sounds"), isOn: model.playSound,
                          help: L("macOS's own sounds: the shutter, recording start, pause and stop, the countdown and copied text. Never in a recording.")) {
                    model.playSound.toggle()
                }
                CheckChip(L("History"), isOn: model.keepHistory,
                          help: L("The last 10 captures in the menu, to copy again or drag into another app. Off forgets them.")) {
                    model.keepHistory.toggle()
                }
            }
        }
    }

    /// "~/Downloads" for folders in the home folder.
    private func displayPath(_ url: URL) -> String {
        let home = NSHomeDirectory()
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

/// What goes into a screen recording.
private struct RecordingGroup: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingsGroup(L("Screen recording")) {
            CompactRow(L("Frame rate"), help: L("60 fps is smoother for motion; 30 fps makes smaller files.")) {
                Segmented(options: [30, 60], selection: $model.recordFramesPerSecond, title: { "\($0) fps" })
            }
            ChipsRow(L("Audio")) {
                CheckChip(L("The Mac's sound"), isOn: model.recordSystemAudio,
                          help: L("What the Mac plays (videos, calls, apps), without Longo Shot's own sounds.")) {
                    model.recordSystemAudio.toggle()
                }
                CheckChip(L("Microphone"), isOn: model.recordMicrophone && AppModel.canRecordMicrophone,
                          help: AppModel.canRecordMicrophone ? L("Your voice, on its own audio track. macOS asks for Microphone access the first time.")
                                                             : L("Needs macOS 15 or later.")) {
                    model.recordMicrophone.toggle()
                }
                .disabled(!AppModel.canRecordMicrophone)
            }
            ChipsRow(L("On screen")) {
                CheckChip(L("Pointer"), isOn: model.recordCursor) { model.recordCursor.toggle() }
                CheckChip(L("Clicks"), isOn: model.recordClicks && model.recordCursor && AppModel.canRecordMicrophone,
                          help: AppModel.canRecordMicrophone ? L("A ring around the pointer at each click.") : L("Needs macOS 15 or later.")) {
                    model.recordClicks.toggle()
                }
                .disabled(!AppModel.canRecordMicrophone || !model.recordCursor)
                CheckChip(L("3 s countdown"), isOn: model.recordCountdown,
                          help: L("3, 2, 1 over the area before recording starts, to get the screen ready. Esc cancels it.")) {
                    model.recordCountdown.toggle()
                }
            }
        }
    }
}
