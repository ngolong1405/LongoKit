import AppKit
import LongoKitUI
import SwiftUI

/// The menu bar popover: a strip of every module, then the picked one's quick controls (or a way to turn it on).
/// Every module's menu is laid out at once, the others hidden, so the popover keeps the tallest one's size and never
/// resizes from module to module.
struct KitMenu: View {
    @EnvironmentObject private var suite: Suite

    var body: some View {
        let selection = suite.menuInfo.id
        VStack(spacing: 0) {
            ModuleStrip(selection: selection)
            ZStack(alignment: .top) {
                ForEach(ModuleInfo.all) { info in
                    let shown = info.id == selection
                    Group {
                        if let host = suite.hosts[info.id] { host.menu } else { OffMenu(info: info) }
                    }
                    .opacity(shown ? 1 : 0)
                    // Hidden menus keep their place (and the popover's size), but not their buttons or shortcuts.
                    .disabled(!shown)
                    .allowsHitTesting(shown)
                    .accessibilityHidden(!shown)
                }
            }
            .frame(width: Theme.hostedMenuWidth)
            // The module's controls change at once; only the strip's tile slides.
            .transaction { $0.animation = nil }
        }
        .background(LinearGradient(colors: [Theme.popoverTop, Theme.popoverBottom], startPoint: .top, endPoint: .bottom))
    }
}

/// Every module, the open one on a tile. Off modules are grey; the others show where they stand.
private struct ModuleStrip: View {
    @EnvironmentObject private var suite: Suite
    let selection: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ModuleInfo.all) { info in
                let active = info.id == selection
                let status = suite.status(info.id)
                Button { suite.menuModule = info.id } label: {
                    HStack(spacing: 6) {
                        ModuleLogo(info: info, size: 18, dimmed: status == .off)
                        Text(info.title)
                            .font(.ui(11, active ? .semibold : .medium))
                            .foregroundStyle(status == .off ? Theme.textFaint : active ? Theme.text : Theme.textMuted)
                            .lineLimit(1)
                        if status != .running { StatusMark(status: status) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .anchorPreference(key: SelectedModuleKey.self, value: .bounds) { active ? $0 : nil }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(help(info, status))
            }
        }
        // One tile behind the open module, sliding to the next one.
        .backgroundPreferenceValue(SelectedModuleKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let rect = proxy[anchor]
                    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                    shape.fill(Theme.segmentSelected)
                        .overlay(shape.strokeBorder(Theme.hairline))
                        .shadow(color: Color.black.opacity(0.1), radius: 1.5, y: 1)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            .animation(Motion.slide, value: selection)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.segmentTrack))
        .padding([.horizontal, .top], 14)
        .padding(.bottom, 2)
    }

    private func help(_ info: ModuleInfo, _ status: Suite.Status) -> String {
        switch status {
        case .running: return info.appName
        case .paused: return L("%@ · paused", info.appName)
        case .elsewhere: return L("%@ · open as its own app", info.appName)
        case .off: return L("%@ · off", info.appName)
        }
    }
}

private struct SelectedModuleKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// A module that isn't running here: off, or open as its own app. Says so, with the way to run it.
private struct OffMenu: View {
    @EnvironmentObject private var suite: Suite
    @Environment(\.openWindow) private var openWindow
    let info: ModuleInfo

    var body: some View {
        let elsewhere = suite.status(info.id) == .elsewhere
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ModuleLogo(info: info, size: 32, dimmed: !elsewhere)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.appName).font(.display(14, .semibold)).foregroundStyle(Theme.text)
                    HStack(spacing: 5) {
                        Image(systemName: elsewhere ? "arrow.up.forward.app" : "power")
                            .font(.system(size: 9, weight: .bold))
                        Text(elsewhere ? L("Open as its own app") : L("Off"))
                            .font(.ui(11))
                    }
                    .foregroundStyle(elsewhere ? Theme.amber : Theme.textFaint)
                }
            }
            Hairline()
            Text(elsewhere ? L("%@ is open as its own app. Quit it so LongoKit runs it instead.", info.appName)
                 : L("This module is off: it takes no memory and asks for no permissions."))
                .font(.ui(12))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if elsewhere {
                    Button(L("Run Here")) { suite.quitOwnApp(info) }
                } else {
                    Button(L("Turn On")) { suite.setEnabled(info, true) }
                }
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
            Hairline()
            MenuFooter {
                suite.page = .module(info.id)
                if !MainWindowRef.show() { openWindow(id: "main") }
            }
        }
        .padding(14)
        .id(suite.language)
    }
}

/// LongoKit's mark in the menu bar: the four modules, one per corner (mouse, display, keyboard, viewfinder). A
/// template, so it follows the menu bar's color.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            let line: CGFloat = 1.3
            func stroke(_ path: NSBezierPath) {
                path.lineWidth = line
                path.stroke()
            }
            // Mouse, top left: the body and its wheel.
            stroke(NSBezierPath(roundedRect: NSRect(x: 2.4, y: 0.9, width: 4.6, height: 7.2), xRadius: 2.3, yRadius: 2.3))
            NSBezierPath.fill(NSRect(x: 4.1, y: 2.4, width: 1.2, height: 2))
            // Display, top right: the screen on its stand.
            stroke(NSBezierPath(roundedRect: NSRect(x: 10.1, y: 1.1, width: 7.2, height: 5), xRadius: 1, yRadius: 1))
            NSBezierPath.fill(NSRect(x: 13.1, y: 6.1, width: 1.2, height: 1.4))
            NSBezierPath.fill(NSRect(x: 11.9, y: 7.4, width: 3.6, height: 1.1))
            // Keyboard, bottom left: three keys and the space bar.
            stroke(NSBezierPath(roundedRect: NSRect(x: 0.7, y: 11, width: 8, height: 5.6), xRadius: 1.2, yRadius: 1.2))
            for x: CGFloat in [2.3, 4.2, 6.1] { NSBezierPath.fill(NSRect(x: x, y: 12.6, width: 1.1, height: 1.1)) }
            NSBezierPath.fill(NSRect(x: 3, y: 14.6, width: 3.4, height: 0.9))
            // Viewfinder, bottom right: four corners round a dot.
            let (left, top, right, bottom, arm): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = (10.4, 10.2, 17.3, 17.1, 2.2)
            let corners = NSBezierPath()
            for (x, y, dx, dy) in [(left, top, arm, arm), (right, top, -arm, arm), (right, bottom, -arm, -arm), (left, bottom, arm, -arm)] {
                corners.move(to: NSPoint(x: x, y: y + dy))
                corners.line(to: NSPoint(x: x, y: y))
                corners.line(to: NSPoint(x: x + dx, y: y))
            }
            stroke(corners)
            NSBezierPath(ovalIn: NSRect(x: 12.6, y: 12.4, width: 2.5, height: 2.5)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppInfo.name
        return image
    }()
}
