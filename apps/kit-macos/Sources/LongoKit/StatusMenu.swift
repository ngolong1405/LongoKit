import AppKit
import LongoKitUI

/// The right-click menu of LongoKit's menu bar icon: Settings, each module's power switch, About and Quit.
@MainActor
enum StatusMenu {
    static func make(_ suite: Suite) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionMenuItem(L("Settings…"), key: ",", image: symbol("gearshape")) { MainWindowRef.show() })
        menu.addItem(.separator())
        for info in ModuleInfo.all { menu.addItem(item(for: info, suite)) }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(L("About"), image: symbol("info.circle")) {
            suite.page = .about
            MainWindowRef.show()
        })
        menu.addItem(ActionMenuItem(L("Quit"), key: "q", image: symbol("power")) { NSApp.terminate(nil) })
        return menu
    }

    /// A module, ticked while it runs: clicking pauses or resumes it. A module that's off turns on; one open as its own
    /// app can't be switched from here.
    private static func item(for info: ModuleInfo, _ suite: Suite) -> NSMenuItem {
        let status = suite.status(info.id)
        let title: String
        switch status {
        case .off: title = L("%@ (off)", info.title)
        case .elsewhere: title = L("%@ (open on its own)", info.title)
        case .running, .attention: title = info.title
        }
        let item = ActionMenuItem(title, image: mark(info, dimmed: status == .off || status == .elsewhere)) {
            switch status {
            case .off: suite.setEnabled(info, true)
            case .running, .attention: suite.setEnabled(info, false)
            case .elsewhere: break
            }
        }
        item.state = status == .running || status == .attention ? .on : .off
        item.isEnabled = status != .elsewhere
        switch status {
        case .running, .attention: item.toolTip = Power.action(info.appName, turningOn: false)
        case .off: item.toolTip = Power.action(info.appName, turningOn: true)
        case .elsewhere: item.toolTip = L("%@ is open as its own app. Quit it so LongoKit runs it instead.", info.appName)
        }
        return item
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    /// The module's small mark at menu size; faded while it isn't running here.
    private static func mark(_ info: ModuleInfo, dimmed: Bool) -> NSImage? {
        guard let source = Resource.image("Marks/\(info.title).png") else { return nil }
        let size = NSSize(width: 16, height: 16)
        return NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: dimmed ? 0.4 : 1)
            return true
        }
    }
}
