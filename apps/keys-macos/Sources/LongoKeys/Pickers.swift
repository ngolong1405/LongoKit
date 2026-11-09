import AppKit
import LongoKitUI
import SwiftUI
import UniformTypeIdentifiers

/// The two "choose what this key does" popovers, built like Longo Mouse's action picker.

/// Fixed so a picker never resizes (and jumps) while searching or switching sections.
private let listHeight: CGFloat = 340

enum Pickers {
    /// Snapshots only: ImageRenderer can't draw text fields or scroll views.
    static var flattened = false
}

/// A scroll view, or the bare list in snapshots.
private struct PickerList<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if Pickers.flattened { Color.clear.overlay(alignment: .top) { content() }.clipped() } else { PickerList { content() } }
    }
}

/// What a key can send instead (Keyboards tab), plus "as it is".
struct TargetPicker: View {
    let key: Key
    let current: Key?
    let choose: (Key?) -> Void
    let dismiss: () -> Void
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PickerHeader(L("REMAP KEY") + " · " + key.name.uppercased(), dismiss: dismiss)
            PickerSearchField("Search keys (e.g. Esc, ⌘, Home)…", query: $query, flattened: Pickers.flattened)
            PickerList {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(KeyboardLayout.targets, id: \.0) { group, keys in
                        let shown = keys.filter(matches)
                        if !shown.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                SectionLabel(text: L(group)).padding(.leading, 4).padding(.bottom, 2)
                                ForEach(shown) { target in
                                    PickerRow(symbol: target.symbol, title: target.pickerTitle, subtitle: L(group),
                                              selected: current == target) { choose(target) }
                                }
                            }
                        }
                    }
                    if KeyboardLayout.targets.allSatisfy({ $0.1.filter(matches).isEmpty }) {
                        Text(L("No matching keys.")).font(.ui(12)).foregroundStyle(Theme.textMuted).padding(8)
                    }
                }
            }
            .frame(height: listHeight)
            PickerFooterRow(symbol: "arrow.uturn.backward", title: L("As it is")) { choose(nil) } trailing: {
                if current == nil { Chip(L("Selected"), tone: .solar) } else { KeyCap(text: key.name) }
            }
        }
        .padding(12)
        .frame(width: 400)
        .pickerBackground()
    }

    private func matches(_ target: Key) -> Bool {
        query.isEmpty || target.pickerTitle.localizedCaseInsensitiveContains(query)
    }
}

/// Hyper actions (Hyper tab): a navigation key, the next input source, an app, or a recorded shortcut.
struct HyperActionPicker: View {
    private enum Section: CaseIterable {
        case standard, shortcut

        var title: String {
            switch self {
            case .standard: return L("Standard")
            case .shortcut: return L("Shortcut Key")
            }
        }
    }

    let key: Key
    let current: HyperAction?
    let choose: (HyperAction?) -> Void
    let dismiss: () -> Void
    @State private var section: Section = .standard
    @State private var query = ""
    @State private var recording = false
    @State private var monitor: Any?

    private static let groups: [(title: String, keys: [Key])] = [
        ("Arrows", [.left, .down, .up, .right]),
        ("Navigation", [.home, .end, .pageUp, .pageDown]),
        ("Editing", [.delete, .forwardDelete, .escape, .returnKey]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PickerHeader(L("ASSIGN ACTION") + " · HYPER + " + key.name.uppercased(), dismiss: dismiss)
            Segmented(options: Section.allCases, selection: $section, title: { $0.title }, stretch: true)
            Group {
                switch section {
                case .standard: standardList
                case .shortcut: shortcutPane
                }
            }
            .frame(height: listHeight, alignment: .top)
            PickerFooterRow(symbol: "arrow.uturn.backward", title: L("No action")) { choose(nil) } trailing: {
                if current == nil { Chip(L("Selected"), tone: .solar) } else { KeyCap(text: "⌃⌥⇧⌘ " + key.name) }
            }
        }
        .padding(12)
        .frame(width: 400)
        .pickerBackground()
        .onAppear { if case .shortcut = current { section = .shortcut } }
        .onDisappear(perform: stopRecording)
    }

    // MARK: Standard

    private var standardList: some View {
        VStack(alignment: .leading, spacing: 8) {
            PickerSearchField("Search actions (e.g. arrows, Home, input source)…", query: $query, flattened: Pickers.flattened)
            PickerList {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Self.groups, id: \.title) { group in
                        let keys = group.keys.filter { matches($0.pickerTitle, group.title) }
                        if !keys.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                SectionLabel(text: L(group.title)).padding(.leading, 4).padding(.bottom, 2)
                                ForEach(keys) { target in
                                    PickerRow(symbol: target.symbol, title: target.pickerTitle, subtitle: L("Sends this key"),
                                              selected: current == .key(target)) { choose(.key(target)) }
                                }
                            }
                        }
                    }
                    if matches(L("Next input source"), "More") || matches(L("Open an app…"), "More") {
                        VStack(alignment: .leading, spacing: 2) {
                            SectionLabel(text: L("More")).padding(.leading, 4).padding(.bottom, 2)
                            if matches(L("Next input source"), "More") {
                                PickerRow(symbol: "globe", title: L("Next input source"),
                                          subtitle: L("Switch keyboard layout, e.g. to Vietnamese"),
                                          selected: current == .nextInputSource) { choose(.nextInputSource) }
                            }
                            if matches(L("Open an app…"), "More") {
                                PickerRow(symbol: "app", title: L("Open an app…"), subtitle: openAppSubtitle,
                                          selected: isOpenApp, action: pickApp)
                            }
                        }
                    }
                }
            }
        }
    }

    private var isOpenApp: Bool {
        if case .openApp = current { return true }
        return false
    }

    private var openAppSubtitle: String {
        isOpenApp ? current!.title : L("Launches or brings it to the front")
    }

    private func matches(_ title: String, _ group: String) -> Bool {
        query.isEmpty || title.localizedCaseInsensitiveContains(query) || L(group).localizedCaseInsensitiveContains(query)
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { choose(.openApp(path: url.path)) }
    }

    // MARK: Shortcut

    private var shortcutPane: some View {
        let label: String? = { if case .shortcut(_, _, let label) = current { return label } else { return nil } }()
        return VStack(spacing: 10) {
            Image(systemName: "command")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(recording ? Theme.magenta : Theme.violetLight)
                .frame(width: 48, height: 48)
                .recessed(radius: 12)
                .shadow(color: Theme.magenta.opacity(recording ? 0.6 : 0), radius: 10)
            if recording {
                Text(L("Press the key combination now…")).font(.display(13, .semibold)).foregroundStyle(Theme.text)
                Text(L("Esc cancels")).font(.mono(10)).foregroundStyle(Theme.textFaint)
            } else if let label {
                Text(L("Sends")).font(.mono(10)).foregroundStyle(Theme.textFaint)
                KeyCap(text: label)
            } else {
                Text(L("No custom shortcut yet")).font(.display(13, .semibold)).foregroundStyle(Theme.text)
                Text(L("Record any key combination, like ⌘⇧4 or ⌥Space.")).font(.ui(11)).foregroundStyle(Theme.textMuted)
            }
            Button(recording ? L("Cancel") : label == nil ? L("Record Shortcut") : L("Record Again")) {
                recording ? stopRecording() : record()
            }
            .buttonStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .recessed(radius: 12)
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

extension Key {
    /// Arrows spelled out: the icon already shows the arrow.
    var pickerTitle: String {
        switch self {
        case .left: return L("← Left Arrow")
        case .right: return L("→ Right Arrow")
        case .up: return L("↑ Up Arrow")
        case .down: return L("↓ Down Arrow")
        case .forwardDelete: return L("⌦ Forward Delete")
        default: return name
        }
    }

    /// The SF Symbol a picker shows next to this key.
    var symbol: String {
        switch self {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .home: return "arrow.up.to.line"
        case .end: return "arrow.down.to.line"
        case .pageUp: return "chevron.up.2"
        case .pageDown: return "chevron.down.2"
        case .delete: return "delete.left"
        case .forwardDelete: return "delete.right"
        case .escape: return "escape"
        case .returnKey: return "return"
        case .tab: return "arrow.right.to.line"
        case .space: return "space"
        case .capsLock: return "capslock"
        case .leftControl, .rightControl: return "control"
        case .leftOption, .rightOption: return "option"
        case .leftCommand, .rightCommand: return "command"
        case .leftShift, .rightShift: return "shift"
        default: return (0x68...0x73).contains(usage) ? "fn" : "keyboard"
        }
    }
}
