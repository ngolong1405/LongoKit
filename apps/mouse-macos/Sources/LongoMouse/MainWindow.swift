import SwiftUI

enum MainTab: CaseIterable {
    case general, devices, about

    var title: String {
        switch self {
        case .general: return L("General")
        case .devices: return L("Devices")
        case .about: return L("About")
        }
    }
}

/// The two pages of a mouse's settings, opened from the Devices tab.
enum DeviceSection: CaseIterable {
    case buttons, scrolling

    var title: String {
        switch self {
        case .buttons: return L("Buttons")
        case .scrolling: return L("Scrolling")
        }
    }
}

struct MainWindow: View {
    @EnvironmentObject private var model: AppModel
    /// Height of the hidden system title bar, which SwiftUI still reserves as a top safe area.
    @State private var titlebarInset: CGFloat = 0

    var body: some View {
        WindowFrame {
            TitleBar()
            TabBar(selection: $model.tab)
            // One fixed height for every page: the window never resizes when switching tabs or pages,
            // and each page starts at the top.
            SlimScrollView(scrollTarget: model.highlighted, resetID: model.deviceSection) {
                TabContent(tab: model.tab)
            }
            .frame(height: Theme.contentHeight)
            // A new page gets a fresh scroll view; Buttons ↔ Scrolling keeps it (so the header and its
            // switcher stay put) and just scrolls back to the top.
            .id(PageID(tab: model.tab, detail: model.showingDeviceDetail))
            // Only the tab pill slides; the page itself swaps instantly.
            .transaction { $0.animation = nil }
            // Soft blur behind an open action picker keeps attention on the popover.
            .blur(radius: model.isPickingAction ? 3 : 0)
            .overlay(Color.black.opacity(model.isPickingAction ? 0.25 : 0).allowsHitTesting(false))
            .animation(.easeOut(duration: 0.2), value: model.isPickingAction)
            WindowFooter(tab: model.tab)
        }
        // Rebuild every view when the language changes so all L() strings update.
        .id(model.language)
        // Pull the content up into the hidden title bar's area. ignoresSafeArea() alone draws there but the
        // window still adds the inset to its height, leaving a transparent strip at the bottom.
        .padding(.top, -titlebarInset)
        .onAppear {
            // `--tab devices` opens on a given tab (handy for screenshots).
            let args = CommandLine.arguments
            if let index = args.firstIndex(of: "--tab"), index + 1 < args.count,
               let tab = MainTab.allCases.first(where: { $0.title.lowercased() == args[index + 1].lowercased() }) {
                model.tab = tab
            }
        }
        .background(WindowConfigurator { titlebarInset = $0 })
    }
}

/// Identifies the page on screen; a new one gets a fresh scroll position.
private struct PageID: Hashable {
    let tab: MainTab
    let detail: Bool
}

struct TabContent: View {
    let tab: MainTab

    var body: some View {
        switch tab {
        case .general: GeneralTab()
        case .devices: DevicesTab()
        case .about: AboutTab()
        }
    }
}

/// Level 0 canvas: matte space black with a faint top-to-bottom gradient over the desktop blur.
struct WindowFrame<Content: View>: View {
    /// Off for snapshots: ImageRenderer can't draw the AppKit blur view.
    var blur = true
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.windowRadius, style: .continuous)
        VStack(spacing: 0) { content }
            .frame(width: Theme.windowWidth)
            .background(
                ZStack {
                    if blur { VisualEffectBackground() }
                    LinearGradient(colors: [Theme.canvasTop.opacity(0.95), Theme.canvas.opacity(0.98)],
                                   startPoint: .top, endPoint: .bottom)
                }
            )
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.rim))
        }
}

struct TitleBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            TrafficLights()
            HStack(spacing: 8) {
                AppLogo(size: 28).padding(-3)
                Text(AppInfo.name)
                    .font(.display(15, .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            StatusPill()
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }
}

/// Compact Running / Paused / Listening indicator.
private struct StatusPill: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let (text, color): (String, Color) = model.isCapturing ? (L("Listening"), Theme.violet)
            : model.isRunning ? (L("Running"), Theme.emerald) : (L("Paused"), Theme.amber)
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.9), radius: 3)
            Text(text).font(.ui(11, .medium)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(color.opacity(0.1)))
        .help(model.isCapturing ? L("Listening for a mouse button to add")
              : model.isRunning ? L("Your custom buttons are active")
              : L("%@ is paused; mouse buttons work as normal", AppInfo.name))
        .animation(.easeOut(duration: 0.2), value: text)
    }
}

/// System / Dark / Light, as three small icons (in the menu bar popover).
struct ThemeSwitcher: View {
    @EnvironmentObject private var model: AppModel
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppAppearance.allCases, id: \.self) { option in
                let selected = model.appearance == option
                Button { withAnimation(Motion.slide) { model.appearance = option } } label: {
                    Image(systemName: symbol(option))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? Theme.solar : Theme.textMuted)
                        .frame(width: 24, height: 20)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Theme.segmentSelected)
                                    .shadow(color: Color.black.opacity(0.12), radius: 1, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tip(option))
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.segmentTrack))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.hairline))
    }

    private func tip(_ option: AppAppearance) -> String {
        switch option {
        case .system: return L("Theme: follow macOS")
        case .dark: return L("Theme: dark")
        case .light: return L("Theme: light")
        }
    }

    private func symbol(_ option: AppAppearance) -> String {
        switch option {
        case .system: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }
}

/// Custom traffic lights so they sit in the taller title bar. Glyphs show on hover like the system ones.
struct TrafficLights: View {
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            light(0xFF5F57, glyph: "xmark", tip: L("Close window (keeps running in the menu bar)")) {
                MainWindowRef.hide()
            }
            light(0xFEBC2E, glyph: "minus", tip: L("Minimize")) { MainWindowRef.window?.miniaturize(nil) }
            light(0x28C840, glyph: "plus", tip: L("This window has a fixed size")) {}
        }
        .onHover { hovering = $0 }
    }

    private func light(_ fill: UInt32, glyph: String, tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: fill))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.15)))
                .overlay(
                    Image(systemName: glyph)
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.6))
                        .opacity(hovering ? 1 : 0)
                )
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
        .help(tip)
    }
}

/// Text-only segmented mode switcher; the active tab is a lifted pill.
struct TabBar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selection: MainTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                item(tab)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.segmentTrack))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.hairline))
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func item(_ tab: MainTab) -> some View {
        let active = tab == selection
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return Button {
            withAnimation(Motion.slide) { selection = tab }
        } label: {
            Text(tab == .devices && !model.connectedDevices.isEmpty ? L("Devices") + " (\(model.connectedDevices.count))" : tab.title)
                .font(.ui(12, active ? .semibold : .medium))
                .foregroundStyle(active ? Theme.text : Theme.textMuted)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background {
                    if active {
                        shape.fill(Theme.segmentSelected)
                            .shadow(color: Color.black.opacity(0.12), radius: 1.5, y: 1)
                            .matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct WindowFooter: View {
    @EnvironmentObject private var model: AppModel
    let tab: MainTab

    var body: some View {
        HStack {
            // About has nothing to restore, so it offers the diagnostics copy there instead.
            if tab == .about {
                Button(action: model.copyDiagnostics) { Label(L("Copy Diagnostics"), systemImage: "doc.on.doc") }
                    .buttonStyle(.ghost)
            } else {
                Button { model.restoreDefaults(for: tab) } label: { Label(L("Restore Defaults"), systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.ghost)
            }
            (Text(L("Crafted by ")) + Text(AppInfo.author).foregroundColor(Theme.solarLight))
                .font(.mono(10))
                .foregroundStyle(Theme.textFaint)
                .padding(.leading, 6)
            Spacer()
            Button { NSApp.terminate(nil) } label: { Label(L("Quit"), systemImage: "power") }
                .buttonStyle(GhostButtonStyle(tint: Theme.solarLight))
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(Theme.chrome)
        .overlay(alignment: .top) { Hairline() }
    }
}

// MARK: - AppKit glue

enum MainWindowRef {
    static weak var window: NSWindow?
    /// Off while the menu bar icon is shown: then a hidden window also hides the Dock icon, like other menu bar apps.
    static var keepsDockIconWhenHidden = false

    /// Closing only hides the window; the app keeps running from the menu bar until Quit.
    static func hide() {
        window?.orderOut(nil)
        if !keepsDockIconWhenHidden { NSApp.setActivationPolicy(.accessory) }
    }

    /// Brings the window (and the Dock icon) back. Returns false when SwiftUI hasn't created the window yet.
    @discardableResult
    static func show() -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return false }
        window.makeKeyAndOrderFront(nil)
        return true
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Turns the SwiftUI window into the borderless, transparent shell the design draws its own chrome in.
struct WindowConfigurator: NSViewRepresentable {
    /// Reports the title bar height that SwiftUI reserves at the top of the window.
    var onTitlebarInset: (CGFloat) -> Void = { _ in }

    func makeNSView(context: Context) -> NSView {
        let view = HostView()
        view.onTitlebarInset = onTitlebarInset
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // The shadow is computed from the content's alpha, so refresh it when the size changes.
        DispatchQueue.main.async { nsView.window?.invalidateShadow() }
    }

    /// Configures the window as soon as the view joins it, instead of hoping an async hop finds it attached.
    private final class HostView: NSView {
        var onTitlebarInset: (CGFloat) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            WindowConfigurator.configure(window)
            let inset = window.frame.height - window.contentLayoutRect.height
            // Report after this layout pass; changing SwiftUI state during it is not allowed.
            DispatchQueue.main.async { [onTitlebarInset] in onTitlebarInset(inset) }
        }
    }

    private static func configure(_ window: NSWindow) {
        MainWindowRef.window = window
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = true
        }
    }
}
