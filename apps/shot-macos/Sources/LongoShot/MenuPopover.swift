import LongoKitUI
import SwiftUI

/// The menu bar menu: every capture with its shortcut, the save folder, settings.
struct MenuPopover: View {
    @EnvironmentObject private var model: AppModel
    /// The menu's own window, closed before a capture starts.
    @State private var window: NSWindow?

    private let captures: [ShotAction] = [.captureArea, .captureWindow, .captureScreen, .captureText, .record]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppLogo(size: 38).padding(-3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppInfo.name).font(.display(14, .semibold)).foregroundStyle(Theme.text)
                    let color = model.hasPermission ? Theme.emerald : Theme.amber
                    HStack(spacing: 5) {
                        Circle().fill(color).frame(width: 6, height: 6).shadow(color: color, radius: 3)
                        Text(model.hasPermission ? L("Ready") : L("Needs permission")).font(.ui(11)).foregroundStyle(color).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                ThemeSwitcher(selection: $model.appearance)
            }
            Hairline()

            VStack(spacing: 2) {
                ForEach(captures) { action in
                    ActionRow(action: action) { run(action) }
                }
            }
            Hairline()
            HStack(spacing: 10) {
                Image(systemName: model.saveToFolder ? "folder.fill" : "doc.on.clipboard")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.solar)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Save to the folder")).font(.ui(13)).foregroundStyle(Theme.text)
                    Text(model.saveToFolder ? L("Saved and copied") : L("Clipboard only"))
                        .font(.ui(11)).foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: 8)
                DSSwitch(isOn: $model.saveToFolder)
            }
            .padding(.horizontal, 8)
            VStack(spacing: 2) {
                ActionRow(action: .copyLast) { run(.copyLast) }
                if model.saveToFolder { ActionRow(action: .openFolder) { run(.openFolder) } }
            }

            Hairline()
            MenuFooter { close(); model.showWindow() }
        }
        .padding(14)
        .frame(width: 320)
        .background(LinearGradient(colors: [Theme.popoverTop, Theme.popoverBottom], startPoint: .top, endPoint: .bottom))
        .background(WindowReader(window: $window))
        .id(model.language)
        .onAppear { model.refreshPermission() }
    }

    /// The menu closes first, so it's gone before the overlay or the capture.
    private func run(_ action: ShotAction) {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { model.perform(action) }
    }

    private func close() {
        window?.close()
    }
}

private struct ActionRow: View {
    @EnvironmentObject private var model: AppModel
    let action: ShotAction
    let perform: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 10) {
                Image(systemName: action.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(action.isComingSoon ? Theme.textFaint : Theme.violet)
                    .frame(width: 20)
                Text(action.title).font(.ui(13)).foregroundStyle(action.isComingSoon ? Theme.textMuted : Theme.text)
                if action.isComingSoon { Chip.soon }
                Spacer(minLength: 8)
                if !action.isComingSoon, let shortcut = model.shortcuts[action] {
                    KeyCaps(shortcut: shortcut, small: true)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Theme.tint(0.07) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The NSWindow a view is in.
private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if window == nil { DispatchQueue.main.async { window = nsView.window } }
    }
}
