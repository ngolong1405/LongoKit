import LongoKitUI
import SwiftUI

/// Popover for choosing what a gesture does: standard macOS actions, a recorded shortcut, or an Apple key.
struct ActionPicker: View {
    enum Section: CaseIterable {
        case standard, shortcut, apple

        var title: String {
            switch self {
            case .standard: return L("Standard")
            case .shortcut: return L("Shortcut Key")
            case .apple: return L("Apple Keys")
            }
        }
    }

    /// An existing gesture, or one that only gets created once the user picks something.
    struct Target {
        let bindingID: UUID
        let trigger: Trigger
        let clickType: ClickType
    }

    @EnvironmentObject private var model: AppModel
    let target: Target
    let dismiss: () -> Void

    @State private var section: Section = .standard
    @State private var query = ""

    /// Snapshots only: ImageRenderer can't draw text fields or scroll views.
    static var flattened = false

    private var bindingID: UUID { target.bindingID }
    private var binding: MouseBinding? { model.editing.first { $0.id == bindingID } }
    private var isPress: Bool { target.clickType.isPress }

    /// Fixed so switching sections swaps the content without resizing (and moving) the popover.
    private static let contentHeight: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if isPress {
                Segmented(options: Section.allCases, selection: $section, title: { $0.title }, stretch: true)
            }
            Group {
                switch section {
                case .standard: standardList
                case .shortcut: shortcutPane
                case .apple: appleKeys
                }
            }
            .frame(height: isPress ? Self.contentHeight : nil, alignment: .top)
            if isPress { recordRow }
        }
        .padding(12)
        .frame(width: 400)
        .background(LinearGradient(colors: [Theme.popoverTop, Theme.popoverBottom], startPoint: .top, endPoint: .bottom))
        .onAppear {
            if binding?.action == .shortcut { section = .shortcut }
            if binding?.action == .mediaKey { section = .apple }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.solar).frame(width: 6, height: 6).shadow(color: Theme.solar, radius: 3)
            Text(headerText).font(.mono(9)).tracking(0.5).foregroundStyle(Theme.textMuted).lineLimit(1)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.plain)
            .help(L("Close without changes"))
        }
    }

    private var headerText: String {
        let gesture = target.clickType == .click ? L("SINGLE CLICK") : target.clickType.caption.uppercased()
        return L("ASSIGN ACTION") + " · \(target.trigger.title.uppercased()) · \(gesture)"
    }

    private func choose(_ action: ActionKind) {
        model.assign(action, to: target.bindingID, trigger: target.trigger, clickType: target.clickType)
        dismiss()
    }

    private func record() {
        model.recordShortcut(for: target.bindingID, creating: (target.trigger, target.clickType))
    }

    // MARK: Standard

    private var standardList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                if Self.flattened {
                    Text(L("Search actions (e.g. Mission Control, Spaces)…")).font(.ui(12)).foregroundStyle(Theme.textFaint)
                    Spacer()
                } else {
                    TextField("Search actions (e.g. Mission Control, Spaces)…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.ui(12))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .recessed()

            scrollable {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(groups, id: \.title) { group in
                        let actions = group.actions.filter(matches)
                        if !actions.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                SectionLabel(text: group.title).padding(.leading, 4).padding(.bottom, 2)
                                ForEach(actions) { ActionRow(action: $0, selected: binding?.action == $0, hint: Self.hint(for: $0)) {
                                    choose($0)
                                } }
                            }
                        }
                    }
                    if groups.allSatisfy({ $0.actions.filter(matches).isEmpty }) {
                        Text(L("No matching actions.")).font(.ui(12)).foregroundStyle(Theme.textMuted).padding(8)
                    }
                }
            }
        }
    }

    @ViewBuilder private func scrollable<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if Self.flattened {
            content()
        } else {
            SlimScrollView(gutter: 18) { content() }
        }
    }

    private var groups: [(title: String, actions: [ActionKind])] {
        switch target.clickType {
        case .drag: return [("Drag Gestures", [.dragSpaces, .dragMissionControl, .dragScroll])]
        case .scroll: return [("Scroll Gestures", [.scrollZoom, .scrollSpaces, .scrollHorizontal])]
        default:
            return [
                ("Window & Mission Control", [.missionControl, .appExpose, .showDesktop, .launchpad]),
                ("Spaces", [.spaceLeft, .spaceRight]),
                ("Navigation", [.back, .forward]),
                ("Clicks & Lookup", [.lookUp, .primaryClick, .secondaryClick, .middleClick, .smartZoom]),
            ]
        }
    }

    private func matches(_ action: ActionKind) -> Bool {
        query.isEmpty || action.title.localizedCaseInsensitiveContains(query)
            || action.category.localizedCaseInsensitiveContains(query)
    }

    /// The system shortcut each action sends, shown as a hint.
    static func hint(for action: ActionKind) -> String? {
        switch action {
        case .lookUp: return "⌃⌘D"
        case .back: return "⌘["
        case .forward: return "⌘]"
        case .appExpose: return "⌃↓"
        case .showDesktop: return L("F11")
        case .spaceLeft: return "⌃←"
        case .spaceRight: return "⌃→"
        case .scrollZoom: return L("⌘± ")
        case .smartZoom: return L("Soon")
        default: return nil
        }
    }

    // MARK: Shortcut

    private var shortcutPane: some View {
        let recording = model.recording == .key(bindingID)
        let current = binding?.action == .shortcut ? binding?.shortcut : nil
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
            } else if let current {
                Text(L("Sends")).font(.mono(10)).foregroundStyle(Theme.textFaint)
                KeyCombo(shortcut: current)
            } else {
                Text(L("No custom shortcut yet")).font(.display(13, .semibold)).foregroundStyle(Theme.text)
                Text(L("Record any key combination, like ⌘⇧4 or ⌥Space.")).font(.ui(11)).foregroundStyle(Theme.textMuted)
            }
            Button(recording ? "Cancel" : current == nil ? "Record Shortcut" : "Record Again") {
                recording ? model.cancelRecording() : record()
            }
            .buttonStyle(recording ? AnyButtonStyle(.ghost) : AnyButtonStyle(.primary))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .recessed(radius: 12)
    }

    // MARK: Apple keys

    private var appleKeys: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: L("Brightness, Media & Volume")).padding(.leading, 4).padding(.bottom, 2)
            ForEach(MediaKey.allCases, id: \.self) { key in
                let selected = binding?.action == .mediaKey && binding?.mediaKey == key
                PickerRow(symbol: key.symbol, title: key.title, subtitle: L("Apple keyboard key"), hint: nil, selected: selected) {
                    model.assign(key, to: target.bindingID, trigger: target.trigger, clickType: target.clickType)
                    dismiss()
                }
            }
        }
    }

    // MARK: Footer

    private var recordRow: some View {
        Button {
            section = .shortcut
            record()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "keyboard").font(.system(size: 12)).foregroundStyle(Theme.violetLight)
                Text(L("Record Custom Key")).font(.ui(12, .medium)).foregroundStyle(Theme.text)
                Spacer()
                if let shortcut = binding?.action == .shortcut ? binding?.shortcut : nil {
                    KeyCombo(shortcut: shortcut)
                } else {
                    Text(L("Not set")).font(.mono(10)).foregroundStyle(Theme.textFaint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.island))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.rim))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ActionRow: View {
    let action: ActionKind
    let selected: Bool
    let hint: String?
    let choose: (ActionKind) -> Void

    var body: some View {
        PickerRow(symbol: action.symbol, title: action.title, subtitle: action.category, hint: hint,
                  selected: selected, enabled: action.isAvailable) { choose(action) }
    }
}

private struct PickerRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let hint: String?
    let selected: Bool
    var enabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? Theme.solar : Theme.violetLight)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.ui(12, .medium)).foregroundStyle(Theme.text)
                    Text(subtitle).font(.ui(10)).foregroundStyle(selected ? Theme.solarLight : Theme.textMuted)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.solarLight)
                    Chip(L("Selected"), tone: .solar)
                } else if let hint {
                    Text(hint)
                        .font(.mono(9, .medium))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.segmentTrack))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hairline))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(shape.fill(selected ? Theme.solar.opacity(0.14) : hovering ? Theme.tint(0.05) : .clear))
            .overlay(shape.strokeBorder(selected ? Theme.solar.opacity(0.3) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 }
    }
}

/// "⌘ + ⇧ + 4" as separate violet key tokens.
struct KeyCombo: View {
    let shortcut: KeyShortcut

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array((shortcut.modifiers.symbols.map(String.init) + [shortcut.keyName]).enumerated()), id: \.offset) { index, key in
                if index > 0 { Text(L("+")).font(.mono(9)).foregroundStyle(Theme.textFaint) }
                KeyCap(text: key)
            }
        }
    }
}

/// Lets a ternary pick between two different button styles.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
