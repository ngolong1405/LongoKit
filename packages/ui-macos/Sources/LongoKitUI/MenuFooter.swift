import AppKit
import SwiftUI

/// The bottom of every LongoKit menu bar menu: Settings… on the left, Quit on the right, each just as wide as its label.
public struct MenuFooter: View {
    public let openSettings: () -> Void

    public init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
    }

    public var body: some View {
        HStack(spacing: 8) {
            MenuFooterButton(title: L("Preferences…"), symbol: "gearshape", tint: Theme.violetLight, action: openSettings)
                .keyboardShortcut(",")
            Spacer(minLength: 0)
            MenuFooterButton(title: L("Quit"), symbol: "power", tint: Theme.danger) { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

/// A button that lights up under the pointer (its icon takes `tint`) and sinks a little while pressed.
public struct MenuFooterButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    public init(title: String, symbol: String, tint: Color, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hovering ? tint : Theme.textMuted)
                Text(title)
                    .font(.ui(12, .medium))
                    .foregroundStyle(hovering ? Theme.text : Theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
        }
        .buttonStyle(PressStyle(hovering: hovering, tint: tint))
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }

    private struct PressStyle: ButtonStyle {
        let hovering: Bool
        let tint: Color

        func makeBody(configuration: Configuration) -> some View {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            let pressed = configuration.isPressed
            return configuration.label
                .background(shape.fill(pressed ? tint.opacity(0.18) : hovering ? tint.opacity(0.1) : Theme.tint(0.04)))
                .overlay(shape.strokeBorder(hovering || pressed ? tint.opacity(0.45) : Theme.tint(0.08)))
                .scaleEffect(pressed ? 0.96 : 1)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: pressed)
                .contentShape(shape)
        }
    }
}

public extension Theme {
    /// Every module's menu is this wide in the LongoKit app, so the popover keeps one size from module to module.
    static let hostedMenuWidth: CGFloat = 380
}

public extension View {
    /// A menu bar popover's width and background. Hosted, the menu takes the host's width and leaves the background to
    /// it, so menus of different heights share one popover without a seam.
    func popoverFrame(width: CGFloat) -> some View {
        modifier(PopoverFrame(width: width))
    }
}

private struct PopoverFrame: ViewModifier {
    let width: CGFloat
    @Environment(\.isHosted) private var isHosted

    func body(content: Content) -> some View {
        content
            .frame(width: isHosted ? Theme.hostedMenuWidth : width)
            .background {
                if !isHosted {
                    LinearGradient(colors: [Theme.popoverTop, Theme.popoverBottom], startPoint: .top, endPoint: .bottom)
                }
            }
    }
}
