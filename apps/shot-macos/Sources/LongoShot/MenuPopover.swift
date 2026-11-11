import LongoKitUI
import SwiftUI

/// The menu bar menu: every capture with its shortcut, the save folder, settings.
struct MenuPopover: View {
    @EnvironmentObject private var model: AppModel
    /// The menu's own window, closed before a capture starts.
    @State private var window: NSWindow?
    /// A Recent capture to open previewed (for snapshots).
    var previewing: HistoryItem.ID?

    private let captures: [ShotAction] = [.captureArea, .captureScreen, .captureText, .record]

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
                    // Pause / Resume only means something while recording.
                    if action == .record && model.isRecordingScreen {
                        ActionRow(action: .pauseRecording) { model.perform(.pauseRecording) }
                    }
                }
            }
            Hairline()
            if model.keepHistory && !model.history.isEmpty {
                RecentGrid(close: close, selected: previewing)
                Hairline()
            }
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
        .onAppear {
            model.refreshPermission()
            model.pruneHistory()
        }
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
        // While recording, Record Screen becomes Stop, with the time, and Pause reads Pause or Resume.
        let stopping = action == .record && model.isRecordingScreen
        let resuming = action == .pauseRecording && model.isRecordingPaused
        Button(action: perform) {
            HStack(spacing: 10) {
                Image(systemName: stopping ? "stop.circle.fill" : resuming ? "play.circle" : action.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(stopping ? Theme.danger : Theme.violet)
                    .frame(width: 20)
                Text(stopping ? L("Stop Recording") : action == .pauseRecording ? (resuming ? L("Resume Recording") : L("Pause Recording"))
                     : action.title).font(.ui(13))
                    .foregroundStyle(stopping ? Theme.danger : Theme.text)
                if stopping {
                    Text(RecordingBar.time(model.recordingSeconds)).font(.mono(11, .semibold)).foregroundStyle(Theme.danger)
                        .frame(width: 56, alignment: .leading)
                }
                Spacer(minLength: 8)
                if let shortcut = model.shortcuts[action] {
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

/// The last captures as small tiles; clicking one opens a larger preview above them, with Copy and the rest.
private struct RecentGrid: View {
    @EnvironmentObject private var model: AppModel
    let close: () -> Void
    @State var selected: HistoryItem.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: L("Recent"))
                Spacer()
                Button(L("Clear")) { selected = nil; model.clearHistory() }
                    .buttonStyle(.plain)
                    .font(.ui(11))
                    .foregroundStyle(Theme.textMuted)
                    .help(L("Forget these captures (files in your save folder stay)"))
            }
            if let item = model.history.first(where: { $0.id == selected }) {
                RecentPreview(item: item, close: close) { selected = nil }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(52), spacing: 6), count: 5), alignment: .leading, spacing: 6) {
                ForEach(model.history) { item in
                    RecentCell(item: item, selected: item.id == selected) {
                        withAnimation(Motion.quick) { selected = selected == item.id ? nil : item.id }
                    }
                }
            }
        }
    }
}

/// A tile: the capture small, a ▶ on recordings. Clicking selects it.
private struct RecentCell: View {
    let item: HistoryItem
    let selected: Bool
    let select: () -> Void
    @State private var image: NSImage?
    @State private var hovering = false

    init(item: HistoryItem, selected: Bool, select: @escaping () -> Void) {
        self.item = item
        self.selected = selected
        self.select = select
        // A thumbnail made before shows at once, without a blank first frame.
        _image = State(initialValue: HistoryThumbnails.shared.cached(item))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Button(action: select) {
            ZStack {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.medium).aspectRatio(contentMode: .fill)
                } else {
                    Theme.tint(0.06)
                }
                if item.isMovie {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
            }
            .frame(width: 52, height: 40)
            .clipShape(shape)
            .overlay(shape.strokeBorder(selected || hovering ? Theme.solar : Theme.hairline, lineWidth: selected ? 2 : hovering ? 1.5 : 1))
            .scaleEffect(hovering && !selected ? 1.05 : 1)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .animation(Motion.quick, value: hovering)
        .onHover { hovering = $0 }
        .help(L("Click to preview"))
        // Made when the menu shows it, from a small read of the file.
        .task(id: item.id) { image = await HistoryThumbnails.shared.load(item) }
    }
}

/// The selected capture, bigger, to drag into another app; Copy (⌘C), Open, Draw, Show in Finder and Remove under it.
private struct RecentPreview: View {
    @EnvironmentObject private var model: AppModel
    let item: HistoryItem
    let close: () -> Void
    let dismiss: () -> Void
    @State private var image: NSImage?
    @State private var copied = false

    init(item: HistoryItem, close: @escaping () -> Void, dismiss: @escaping () -> Void) {
        self.item = item
        self.close = close
        self.dismiss = dismiss
        _image = State(initialValue: HistoryThumbnails.shared.cached(item, size: HistoryThumbnails.previewSize)
                       ?? HistoryThumbnails.shared.cached(item))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                Theme.well
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if item.isMovie, let duration = item.duration {
                    Label(RecordingBar.time(duration), systemImage: "play.fill")
                        .font(.mono(10, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .padding(8)
                }
            }
            .frame(height: 168)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.hairline))
            .onDrag { NSItemProvider(contentsOf: item.file) ?? NSItemProvider() }
            .help(L("Drag into another app"))

            HStack(spacing: 6) {
                Button {
                    model.copy(item)
                    copied = true
                } label: {
                    Label(copied ? L("Copied") : L("Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .keyboardShortcut("c")
                .help(L("Copy it again (⌘C)"))
                Spacer(minLength: 4)
                icon("arrow.up.forward.app", L("Open")) { close(); model.open(item) }
                if !item.isMovie { icon("pencil.tip", L("Draw on it")) { close(); model.draw(item) } }
                if !item.cached { icon("folder", L("Show in Finder")) { close(); model.showInFinder(item) } }
                icon("trash", L("Remove from Recent")) { dismiss(); model.remove(item) }
            }
        }
        .task(id: item.id) {
            copied = false
            image = await HistoryThumbnails.shared.load(item, size: HistoryThumbnails.previewSize) ?? image
        }
    }

    private func icon(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(GhostButtonStyle(compact: true))
            .help(help)
    }
}
