import SwiftUI

/// The pieces every "choose what this does" popover is built from, so they look the same in every app:
/// a glowing-dot caption with a close button, a search field, and rows with an icon, a subtitle and a
/// "Selected" chip.

/// "● ASSIGN ACTION · BUTTON 5 · SINGLE CLICK" with a close button.
public struct PickerHeader: View {
    let text: String
    let dismiss: () -> Void

    public init(_ text: String, dismiss: @escaping () -> Void) {
        self.text = text
        self.dismiss = dismiss
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.solar).frame(width: 6, height: 6).shadow(color: Theme.solar, radius: 3)
            Text(text).font(.mono(9)).tracking(0.5).foregroundStyle(Theme.textMuted).lineLimit(1)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.plain)
            .help(L("Close without changes"))
        }
    }
}

/// The recessed search field at the top of a picker's list.
public struct PickerSearchField: View {
    let placeholder: String
    @Binding var query: String
    /// Snapshots only: ImageRenderer can't draw text fields.
    let flattened: Bool

    public init(_ placeholder: String, query: Binding<String>, flattened: Bool = false) {
        self.placeholder = placeholder
        _query = query
        self.flattened = flattened
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            if flattened {
                Text(L(placeholder)).font(.ui(12)).foregroundStyle(Theme.textFaint)
                Spacer()
            } else {
                TextField(L(placeholder), text: $query)
                    .textFieldStyle(.plain)
                    .font(.ui(12))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .recessed()
    }
}

/// One choice: icon, title and subtitle; selected it turns orange with a "Selected" chip, otherwise it can
/// show a hint (the shortcut it sends) on the right.
public struct PickerRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let hint: String?
    let selected: Bool
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    public init(symbol: String, title: String, subtitle: String, hint: String? = nil, selected: Bool,
                enabled: Bool = true, action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.hint = hint
        self.selected = selected
        self.enabled = enabled
        self.action = action
    }

    public var body: some View {
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

/// The boxed row at a picker's foot ("Record Custom Key … Not set").
public struct PickerFooterRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let action: () -> Void
    let trailing: Trailing

    public init(symbol: String, title: String, action: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.title = title
        self.action = action
        self.trailing = trailing()
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Theme.violetLight)
                Text(title).font(.ui(12, .medium)).foregroundStyle(Theme.text)
                Spacer()
                trailing
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

public extension View {
    /// A picker popover's solid backdrop, the same as the menu bar popover's.
    func pickerBackground() -> some View {
        background(LinearGradient(colors: [Theme.popoverTop, Theme.popoverBottom], startPoint: .top, endPoint: .bottom))
    }
}
