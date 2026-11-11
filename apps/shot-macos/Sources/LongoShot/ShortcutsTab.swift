import Carbon.HIToolbox
import LongoKitUI
import SwiftUI

struct ShortcutsTab: View {
    @EnvironmentObject private var model: AppModel

    private let groups: [(String, [ShotAction])] = [
        ("Capture", [.captureArea, .captureWindow, .captureScreen, .captureText, .record]),
        ("Quick access", [.copyLast, .openFolder, .openSettings]),
    ]

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(symbol: "command", title: L("Shortcuts"),
                           subtitle: L("Click a shortcut, then press the keys you want. They work in every app, with no permission needed."),
                           tint: Theme.violet) {
                    Button { model.resetShortcuts() } label: { Label(L("Reset"), systemImage: "arrow.counterclockwise") }
                        .buttonStyle(GhostButtonStyle(compact: true))
                        .help(L("Back to the default shortcuts"))
                }
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(Theme.textFaint)
                    Text(L("While recording: Esc cancels, ⌫ removes the shortcut."))
                }
                .font(.ui(11))
                .foregroundStyle(Theme.textMuted)
            }
            .panel()

            ForEach(groups, id: \.0) { title, actions in
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: L(title)).padding(.bottom, 10)
                    ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                        if index > 0 { Hairline().padding(.vertical, 10) }
                        ShortcutRow(action: action)
                    }
                }
                .panel()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

private struct ShortcutRow: View {
    @EnvironmentObject private var model: AppModel
    let action: ShotAction

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                GlyphTile(tint: action.isComingSoon ? Theme.textFaint : Theme.violet, size: 30) {
                    Image(systemName: action.symbol).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(action.isComingSoon ? Theme.textFaint : Theme.violet)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(action.title).font(.ui(13, .medium)).foregroundStyle(Theme.text)
                        if action.isComingSoon { Chip.soon }
                    }
                    Text(action.detail).font(.ui(11)).foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if !action.isComingSoon {
                    ShortcutRecorder(action: action)
                }
            }
            if let note {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
                    Text(note).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .font(.ui(11))
                .padding(.leading, 42)
            }
        }
    }

    private var note: String? {
        if let error = model.shortcutError, error.action == action { return error.text }
        guard model.recording != action, model.shortcuts[action] != nil else { return nil }
        if model.takenShortcuts.contains(action) {
            return L("Another app already uses this shortcut, so it won't work here. Pick another one.")
        }
        if model.systemShortcuts.contains(action) {
            return L("macOS uses this shortcut too. Turn it off in System Settings › Keyboard › Keyboard Shortcuts, or pick another one.")
        }
        return nil
    }
}

/// Click, then press a key combination. Esc cancels, Delete removes the shortcut.
struct ShortcutRecorder: View {
    @EnvironmentObject private var model: AppModel
    let action: ShotAction
    @StateObject private var monitor = KeyMonitor()

    private var isRecording: Bool { model.recording == action }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 4) {
                    if isRecording {
                        Circle().fill(Theme.solar).frame(width: 6, height: 6).shadow(color: Theme.solar, radius: 3)
                        Text(monitor.modifiers == 0 ? L("Press keys…") : Shortcut.symbols(monitor.modifiers) + "…")
                            .font(.mono(12, .medium))
                            .foregroundStyle(Theme.solarLight)
                    } else if let shortcut = model.shortcuts[action] {
                        KeyCaps(shortcut: shortcut)
                    } else {
                        Text(L("Record Shortcut")).font(.ui(12)).foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(width: 150, height: 30)
                .recessed()
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isRecording ? Theme.solar : Color.clear, lineWidth: 1.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isRecording ? L("Press the new shortcut · Esc cancels · ⌫ removes it") : L("Click to record a new shortcut"))

            Button { stop(); model.clearShortcut(action) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textMuted)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Theme.tint(0.06)))
            }
            .buttonStyle(.plain)
            .opacity(model.shortcuts[action] == nil || isRecording ? 0 : 1)
            .disabled(model.shortcuts[action] == nil || isRecording)
            .help(L("Remove this shortcut"))
        }
        .onChange(of: model.recording) { _, recording in
            if recording != action { monitor.stop() }
        }
        .onDisappear { if isRecording { stop() } }
    }

    private func toggle() {
        if isRecording { stop() } else { start() }
    }

    private func start() {
        model.beginRecording(action)
        monitor.start { event in
            let shortcut = Shortcut(event: event)
            switch (Int(event.keyCode), shortcut.modifiers) {
            case (kVK_Escape, 0):
                stop()
            case (kVK_Delete, 0), (kVK_ForwardDelete, 0):
                stop()
                model.clearShortcut(action)
            default:
                // A combination that can't be used stays on screen with the reason; recording goes on.
                if model.setShortcut(shortcut, for: action) { stop() }
            }
        } onCancel: {
            stop()
        }
    }

    private func stop() {
        monitor.stop()
        model.endRecording()
    }
}

/// The keys of a shortcut as separate caps: ⌥ ⇧ 1.
struct KeyCaps: View {
    let shortcut: Shortcut
    var small = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Text(part)
                    .font(.mono(small ? 10 : 12, .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, small ? 4 : 6)
                    .frame(minWidth: small ? 16 : 22, minHeight: small ? 16 : 22)
                    .background(RoundedRectangle(cornerRadius: small ? 4 : 5, style: .continuous).fill(Theme.tint(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: small ? 4 : 5, style: .continuous).strokeBorder(Theme.tint(0.1)))
            }
        }
    }

    private var parts: [String] {
        Shortcut.symbols(shortcut.modifiers).map(String.init) + [Shortcut.keyName(shortcut.keyCode)]
    }
}

/// Watches the keyboard while a shortcut is recorded: key presses go to `onKey` and don't reach the app.
/// Recording stops when the window loses focus.
@MainActor
final class KeyMonitor: ObservableObject {
    /// The modifiers held right now, to show while recording.
    @Published private(set) var modifiers = 0
    private var monitor: Any?
    private var resignObserver: Any?

    func start(onKey: @escaping (NSEvent) -> Void, onCancel: @escaping () -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            if event.type == .flagsChanged {
                self?.modifiers = Shortcut.carbon(event.modifierFlags)
            } else if !event.isARepeat {
                onKey(event)
            }
            return nil
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil,
                                                                queue: .main) { notification in
            guard (notification.object as? NSWindow) === MainWindowRef.window else { return }
            MainActor.assumeIsolated { onCancel() }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        modifiers = 0
    }
}
