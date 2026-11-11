import SwiftUI

// The General tab's compact style, shared by the LongoKit apps: a few cards of one-line settings, a name on the
// left and its control on the right. What a setting does is in its tooltip instead of under it.

/// One card of compact rows under an optional heading. Each row draws a hairline above itself; the card hides the
/// first one.
public struct SettingsGroup<Content: View>: View {
    public var title: String?
    @ViewBuilder public let content: Content

    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.ui(13, .semibold)).foregroundStyle(Theme.text).padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.top, -1)
                .clipped()
                .panel(padding: 0)
        }
    }
}

public extension View {
    /// A row of a `SettingsGroup`: side padding, the row height, and the hairline above it.
    func settingsRow(minHeight: CGFloat = 46) -> some View {
        self.padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .overlay(alignment: .top) { Hairline().padding(.horizontal, 16) }
    }
}

/// A setting on one line: its name, and its control on the right. `help` shows from the ⓘ next to the name.
public struct CompactRow<Accessory: View>: View {
    public let title: String
    public var help: String?
    public var tint: Color?
    public var soon = false
    @ViewBuilder public let accessory: Accessory

    public init(_ title: String, help: String? = nil, tint: Color? = nil, soon: Bool = false,
                @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.help = help
        self.tint = tint
        self.soon = soon
        self.accessory = accessory()
    }

    public var body: some View {
        HStack(spacing: 12) {
            if let tint {
                Circle().fill(tint).frame(width: 6, height: 6).shadow(color: tint.opacity(0.8), radius: 3)
            }
            Text(title).font(.ui(13, .medium)).foregroundStyle(Theme.text).lineLimit(1)
            if soon { Chip.soon }
            if let help { InfoTip(help) }
            Spacer(minLength: 12)
            accessory
        }
        .settingsRow()
    }
}

/// ⓘ that explains a setting: a click opens the explanation in a bubble, and it shows on hover as well.
public struct InfoTip: View {
    public let text: String
    @State private var shown = false
    @State private var hovering = false

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: shown ? "info.circle.fill" : "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(shown || hovering ? Theme.violetLight : Theme.textFaint)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(text)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .font(.ui(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(14)
        }
    }
}

/// A permission on one line: granted, or a button to grant it.
public struct PermissionLine: View {
    public let title: String
    public var help: String?
    public let granted: Bool
    public let grant: () -> Void

    public init(_ title: String, help: String? = nil, granted: Bool, grant: @escaping () -> Void) {
        self.title = title
        self.help = help
        self.granted = granted
        self.grant = grant
    }

    public var body: some View {
        CompactRow(title, help: help, tint: granted ? Theme.emerald : Theme.amber) {
            if granted {
                Chip(L("Granted"), tone: .emerald)
            } else {
                Button(L("Grant Access…"), action: grant).buttonStyle(PrimaryButtonStyle(compact: true))
            }
        }
    }
}

/// Language, look, start at login and the menu bar icon: the same four rows in every app.
public struct AppBehaviorRows: View {
    @Binding public var language: AppLanguage
    @Binding public var appearance: AppAppearance
    public let startAtLogin: Bool
    public let setStartAtLogin: (Bool) -> Void
    @Binding public var showMenuBarIcon: Bool
    public var menuBarHelp: String?

    public init(language: Binding<AppLanguage>, appearance: Binding<AppAppearance>, startAtLogin: Bool,
                setStartAtLogin: @escaping (Bool) -> Void, showMenuBarIcon: Binding<Bool>, menuBarHelp: String? = nil) {
        self._language = language
        self._appearance = appearance
        self.startAtLogin = startAtLogin
        self.setStartAtLogin = setStartAtLogin
        self._showMenuBarIcon = showMenuBarIcon
        self.menuBarHelp = menuBarHelp
    }

    public var body: some View {
        SettingsGroup(L("App")) {
            CompactRow(L("Language")) {
                Segmented(options: AppLanguage.allCases, selection: $language, title: { $0.title })
            }
            CompactRow(L("Appearance")) {
                ThemeSwitcher(selection: $appearance, large: true)
            }
            CompactRow(L("Start at Login")) {
                DSSwitch(isOn: startAtLogin) { setStartAtLogin(!startAtLogin) }
            }
            CompactRow(L("Show icon in menu bar"), help: menuBarHelp) {
                DSSwitch(isOn: $showMenuBarIcon)
            }
        }
    }
}

public extension Theme {
    /// The page area's height for a page of `content` height: as tall as the page, up to `contentHeight`
    /// (taller pages scroll), and never so short that the window looks empty.
    static func pageHeight(_ content: CGFloat) -> CGFloat {
        min(max(content.rounded(), 260), contentHeight)
    }
}

/// Several on/off choices under one name: the name on top, the choices as checkbox chips in a row below.
public struct ChipsRow<Content: View>: View {
    public let title: String
    public var help: String?
    @ViewBuilder public let content: Content

    public init(_ title: String, help: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.help = help
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Text(title).font(.ui(13, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                if let help { InfoTip(help) }
            }
            HStack(spacing: 8) { content }
        }
        .padding(.vertical, 12)
        .settingsRow()
    }
}

/// An on/off choice as a chip with a checkbox: tinted Solar Amber while on. The whole chip is the button.
public struct CheckChip: View {
    public let title: String
    public let isOn: Bool
    public var help: String?
    public let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    public init(_ title: String, isOn: Bool, help: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isOn = isOn
        self.help = help
        self.action = action
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let box = RoundedRectangle(cornerRadius: 4, style: .continuous)
        Button(action: action) {
            HStack(spacing: 7) {
                ZStack {
                    if isOn {
                        box.fill(Theme.solar)
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                    } else {
                        box.strokeBorder(Theme.tint(0.25), lineWidth: 1.2)
                    }
                }
                .frame(width: 14, height: 14)
                Text(title).font(.ui(12, .medium)).foregroundStyle(isOn ? Theme.text : Theme.textSecondary).fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(shape.fill(isOn ? Theme.solar.opacity(0.1) : Theme.tint(hovering ? 0.07 : 0.035)))
            .overlay(shape.strokeBorder(isOn ? Theme.solar.opacity(0.35) : Theme.hairline))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .help(help ?? "")
        .animation(Motion.quick, value: isOn)
    }
}
