import SwiftUI

/// An app's on/off, said and switched the same way everywhere: its menu, its General tab, its title bar, and in
/// LongoKit its sidebar, General page and right-click menu.
public enum Power {
    /// "On" / "Off" as a state. The words live here, not in the apps' tables, where "Off" also names settings.
    public static func label(_ isOn: Bool) -> String {
        Localizer.language == .vietnamese ? (isOn ? "Đang bật" : "Đang tắt") : (isOn ? "On" : "Off")
    }

    /// "Longo Keys is on" / "is off".
    public static func title(_ name: String, _ isOn: Bool) -> String {
        Localizer.language == .vietnamese ? "\(name) \(isOn ? "đang bật" : "đang tắt")" : "\(name) is \(isOn ? "on" : "off")"
    }

    /// "Turn Longo Keys on" / "off", for the switch's tooltip.
    public static func action(_ name: String, turningOn: Bool) -> String {
        Localizer.language == .vietnamese ? "\(turningOn ? "Bật" : "Tắt") \(name)" : "Turn \(name) \(turningOn ? "on" : "off")"
    }

    /// Green while on, amber while on but held back (a missing permission), grey while off.
    public static func color(_ isOn: Bool, attention: Bool = false) -> Color {
        !isOn ? Theme.textFaint : attention ? Theme.amber : Theme.emerald
    }
}

/// The light and word under an app's name in its menu: On, Off, or what's holding it back.
public struct PowerLabel: View {
    public let isOn: Bool
    public var attention: String?

    public init(isOn: Bool, attention: String? = nil) {
        self.isOn = isOn
        self.attention = isOn ? attention : nil
    }

    public var body: some View {
        let color = Power.color(isOn, attention: attention != nil)
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: isOn ? color : .clear, radius: 3)
            Text(attention ?? Power.label(isOn)).font(.ui(11)).foregroundStyle(isOn ? color : Theme.textMuted).lineLimit(1)
        }
    }
}

/// The first row of an app's General tab: "Longo Keys is on" and the switch, the same switch as in its menu.
public struct PowerRow: View {
    public let name: String
    public let isOn: Bool
    public var help: String?
    public var attention: String?
    public let toggle: () -> Void

    public init(name: String, isOn: Bool, help: String? = nil, attention: String? = nil, toggle: @escaping () -> Void) {
        self.name = name
        self.isOn = isOn
        self.help = help
        self.attention = isOn ? attention : nil
        self.toggle = toggle
    }

    public var body: some View {
        CompactRow(Power.title(name, isOn), help: help, tint: Power.color(isOn, attention: attention != nil)) {
            if let attention { Chip(attention, tone: .amber) }
            DSSwitch(isOn: isOn, action: toggle)
                .help(Power.action(name, turningOn: !isOn))
        }
    }
}

/// The power button in an app's menu header, next to the theme switcher: lit while on.
public struct AppPowerButton: View {
    public let name: String
    public let isOn: Bool
    public var shortcut: String?
    public let toggle: () -> Void

    public init(name: String, isOn: Bool, shortcut: String? = nil, toggle: @escaping () -> Void) {
        self.name = name
        self.isOn = isOn
        self.shortcut = shortcut
        self.toggle = toggle
    }

    public var body: some View {
        Button(action: toggle) {
            Image(systemName: "power").font(.system(size: 12, weight: .bold))
                .foregroundStyle(isOn ? Color.white : Theme.textMuted)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isOn ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.slate))
                )
                .shadow(color: Theme.solar.opacity(isOn ? 0.45 : 0), radius: 6)
        }
        .buttonStyle(.plain)
        .help(Power.action(name, turningOn: !isOn) + (shortcut.map { " (\($0))" } ?? ""))
    }
}
