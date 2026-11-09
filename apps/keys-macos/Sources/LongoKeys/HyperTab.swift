import LongoKitUI
import SwiftUI
import UniformTypeIdentifiers

/// The Hyper layer: what each key does while Caps Lock (set to Hyper) is held.
struct HyperTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(symbol: "command", title: L("Hyper Layer"),
                           subtitle: L("Hold Caps Lock and press a key. Keys without an action send ⌃⌥⇧⌘ + the key, free for any app's shortcuts."),
                           tint: Theme.solar) {
                    if model.usesHyper {
                        Chip(L("In use"), tone: .emerald, dot: true)
                    } else {
                        Button(L("Use Caps Lock as Hyper")) { model.change(nil) { $0.caps = .hyper } }.buttonStyle(.primary)
                    }
                }
                if !model.usesHyper {
                    Text(L("No keyboard has Caps Lock set to Hyper yet: this sets it for every keyboard that uses the shared settings."))
                        .font(.ui(11)).foregroundStyle(Theme.textMuted)
                }
                if model.usesHyper && !model.hasAccessibility {
                    Text(L("Hyper needs Accessibility permission (General tab)."))
                        .font(.ui(11)).foregroundStyle(Theme.amber)
                }
            }
            .panel()

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: L("Click a key to set its action"))
                VStack(spacing: 6) {
                    ForEach(["qwertyuiop", "asdfghjkl", "zxcvbnm"], id: \.self) { row in
                        HStack(spacing: 6) {
                            ForEach(Array(row), id: \.self) { letter in
                                HyperKey(key: .letter(letter))
                            }
                        }
                    }
                    HyperKey(key: .space, label: "Space", wide: true)
                }
                .frame(maxWidth: .infinity)
            }
            .panel()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

extension HyperAction {
    var title: String {
        switch self {
        case .key(let key): return key.name
        case .openApp(let path): return ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        case .shortcut(_, _, let label): return label
        case .nextInputSource: return L("Input source")
        }
    }

    var symbol: String {
        switch self {
        case .key: return "arrow.right.square"
        case .openApp: return "app"
        case .shortcut: return "command"
        case .nextInputSource: return "globe"
        }
    }
}

private struct HyperKey: View {
    @EnvironmentObject private var model: AppModel
    let key: Key
    var label: String? = nil
    var wide = false
    @State private var picking = false

    var body: some View {
        let action = model.binding(for: key)?.action
        Button { picking = true } label: {
            VStack(spacing: 2) {
                Text(label ?? key.name).font(.display(13, .semibold))
                Text(action?.title ?? "⌃⌥⇧⌘").font(.mono(8, .bold)).lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(action == nil ? Theme.textFaint : Color.white.opacity(0.9))
            }
            .foregroundStyle(action == nil ? Theme.text : Color.white)
            .frame(width: wide ? 300 : 66, height: 50)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(action == nil ? AnyShapeStyle(Theme.tint(0.06)) : AnyShapeStyle(Theme.accentGradient)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            ActionPicker(key: key, current: action) { new in
                picking = false
                model.setBinding(key, new)
            }
        }
    }
}

/// Hyper actions: a navigation key, the next input source, an app, or a recorded shortcut.
private struct ActionPicker: View {
    let key: Key
    let current: HyperAction?
    let choose: (HyperAction?) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    private let keys: [Key] = [.left, .down, .up, .right, .home, .end, .pageUp, .pageDown, .forwardDelete, .delete, .escape, .returnKey]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hyper + " + key.name).font(.display(14, .semibold)).foregroundStyle(Theme.text)
            Text(L("KEYS")).font(.mono(9, .semibold)).foregroundStyle(Theme.textFaint)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(70), spacing: 6), count: 4), spacing: 6) {
                ForEach(keys) { target in
                    option(target.name, selected: current == .key(target)) { choose(.key(target)) }
                }
            }
            Text(L("MORE")).font(.mono(9, .semibold)).foregroundStyle(Theme.textFaint)
            HStack(spacing: 6) {
                Button { choose(.nextInputSource) } label: { Label(L("Next input source"), systemImage: "globe") }
                Button(action: pickApp) { Label(L("Open an app…"), systemImage: "app") }
                Button(action: record) { Label(recording ? L("Press keys…") : L("Record shortcut…"), systemImage: "record.circle") }
            }
            .buttonStyle(.ghost)
            .font(.ui(11))
            Hairline()
            Button { choose(nil) } label: { Label(L("No action: send ⌃⌥⇧⌘ + %@", key.name), systemImage: "arrow.uturn.backward") }
                .buttonStyle(.ghost)
        }
        .padding(14)
        .onDisappear(perform: stopRecording)
    }

    private func option(_ title: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.ui(11, .medium)).lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 70, height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.tint(0.07))))
                .foregroundStyle(selected ? Color.white : Theme.text)
        }
        .buttonStyle(.plain)
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { choose(.openApp(path: url.path)) }
    }

    /// The next key pressed, with its modifiers, becomes the shortcut. Esc alone cancels.
    private func record() {
        stopRecording()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if event.keyCode == 53 && mods.isEmpty { stopRecording(); return nil }
            var flags = CGEventFlags()
            var label = ""
            if mods.contains(.control) { flags.insert(.maskControl); label += "⌃" }
            if mods.contains(.option) { flags.insert(.maskAlternate); label += "⌥" }
            if mods.contains(.shift) { flags.insert(.maskShift); label += "⇧" }
            if mods.contains(.command) { flags.insert(.maskCommand); label += "⌘" }
            label += Key.usage(forKeyCode: Int(event.keyCode))?.name ?? (event.charactersIgnoringModifiers?.uppercased() ?? "?")
            stopRecording()
            choose(.shortcut(keyCode: Int(event.keyCode), flags: flags.rawValue, label: label))
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
