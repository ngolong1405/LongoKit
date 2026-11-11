import LongoKitUI
import SwiftUI

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
            .frame(width: wide ? 260 : 54, height: 48)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(action == nil ? AnyShapeStyle(Theme.tint(0.06)) : AnyShapeStyle(Theme.accentGradient)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            HyperActionPicker(key: key, current: action) { new in
                picking = false
                model.setBinding(key, new)
            } dismiss: { picking = false }
        }
        .onChange(of: picking) { model.isPicking = $0 }
    }
}
