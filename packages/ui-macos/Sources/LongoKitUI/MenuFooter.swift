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
            MenuFooterButton(title: L("Settings…"), symbol: "gearshape", tint: Theme.violetLight, action: openSettings)
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

/// The app's menu bar icon beyond its popover: a short menu on right-click (or control-click), and the main window
/// on a double click. A single click still opens the popover.
@MainActor
public enum StatusItemMenu {
    private static var monitor: Any?

    /// `make` builds the menu each time, so it shows the current state; `doubleClick` opens the main window.
    public static func install(doubleClick: @escaping () -> Void, _ make: @escaping () -> NSMenu) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            guard let window = event.window, String(describing: type(of: window)) == "NSStatusBarWindow",
                  let view = window.contentView else { return event }
            if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
                NSMenu.popUpContextMenu(make(), with: event, for: view)
                return nil
            }
            // The second click of a double click closes the popover the first one opened; then the window opens.
            if event.clickCount == 2 { DispatchQueue.main.async(execute: doubleClick) }
            return event
        }
    }
}

/// A menu item that runs a closure.
public final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    public init(_ title: String, key: String = "", image: NSImage? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
        self.image = image
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

public extension StatusItemMenu {
    /// A stand-alone app's right-click menu: Settings, the app's own switch (ticked while it runs), About, Quit.
    static func standard(name: String, icon: NSImage?, isOn: Bool, toggle: @escaping () -> Void,
                         settings: @escaping () -> Void, about: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let symbol = { (name: String) in NSImage(systemSymbolName: name, accessibilityDescription: nil) }
        menu.addItem(ActionMenuItem(L("Settings…"), key: ",", image: symbol("gearshape"), handler: settings))
        menu.addItem(.separator())
        let small = icon.map { source in
            NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                source.draw(in: rect)
                return true
            }
        }
        let power = ActionMenuItem(name, image: small, handler: toggle)
        power.state = isOn ? .on : .off
        power.toolTip = Power.action(name, turningOn: !isOn)
        menu.addItem(power)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(L("About"), image: symbol("info.circle"), handler: about))
        menu.addItem(ActionMenuItem(L("Quit"), key: "q", image: symbol("power")) { NSApp.terminate(nil) })
        return menu
    }
}
