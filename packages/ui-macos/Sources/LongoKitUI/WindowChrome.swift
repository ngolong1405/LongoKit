import AppKit
import SwiftUI

// The custom window shell shared by the LongoKit apps: a borderless, translucent window that draws its own
// traffic lights and tab bar, and only hides (instead of closing) so the app keeps running in the menu bar.

/// Level 0 canvas: matte space black with a faint top-to-bottom gradient over the desktop blur.
public struct WindowFrame<Content: View>: View {
    /// Off for snapshots: ImageRenderer can't draw the AppKit blur view.
    public var blur = true
    @ViewBuilder public let content: Content

    public init(blur: Bool = true, @ViewBuilder content: () -> Content) {
        self.blur = blur
        self.content = content()
    }

    public var body: some View {
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

/// System / Dark / Light, as three small icons.
public struct ThemeSwitcher: View {
    @Binding public var selection: AppAppearance
    /// Settings-row size, matching the Segmented controls next to it; the default is the compact menu size.
    public var large = false
    @Namespace private var pill

    public init(selection: Binding<AppAppearance>, large: Bool = false) {
        self._selection = selection
        self.large = large
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(AppAppearance.allCases, id: \.self) { option in
                let selected = selection == option
                Button { withAnimation(Motion.slide) { selection = option } } label: {
                    Image(systemName: symbol(option))
                        .font(.system(size: large ? 13 : 11, weight: .semibold))
                        .foregroundStyle(selected ? Theme.solar : Theme.textMuted)
                        .frame(width: large ? 40 : 24, height: large ? 28 : 20)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: large ? 7 : 5, style: .continuous)
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
        .padding(large ? 3 : 2)
        .background(RoundedRectangle(cornerRadius: large ? 9 : 7, style: .continuous).fill(Theme.segmentTrack))
        .overlay(RoundedRectangle(cornerRadius: large ? 9 : 7, style: .continuous).strokeBorder(Theme.hairline))
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
public struct TrafficLights: View {
    @State private var hovering = false

    public init() {}

    public var body: some View {
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

/// Text-only segmented tab switcher; the active tab is a lifted pill.
public struct PillTabBar<Tab: Hashable>: View {
    public let tabs: [Tab]
    @Binding public var selection: Tab
    public let title: (Tab) -> String
    @Namespace private var pill

    public init(tabs: [Tab], selection: Binding<Tab>, title: @escaping (Tab) -> String) {
        self.tabs = tabs
        self._selection = selection
        self.title = title
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { tab in
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

    private func item(_ tab: Tab) -> some View {
        let active = tab == selection
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return Button {
            withAnimation(Motion.slide) { selection = tab }
        } label: {
            Text(title(tab))
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

// MARK: - AppKit glue

public enum MainWindowRef {
    public static weak var window: NSWindow?
    /// Off while the menu bar icon is shown: then a hidden window also hides the Dock icon, like other menu bar apps.
    public static var keepsDockIconWhenHidden = false

    /// Closing only hides the window; the app keeps running from the menu bar until Quit. The window's
    /// content is dropped while hidden (see `ReleasedWhenHidden`), so a closed window costs no memory or updates.
    public static func hide() {
        if let size = window?.contentView?.frame.size { WindowVisibility.shared.hiddenSize = size }
        window?.orderOut(nil)
        WindowVisibility.shared.isShown = false
        if !keepsDockIconWhenHidden { NSApp.setActivationPolicy(.accessory) }
        // Give the memory the torn-down views used back to macOS, once SwiftUI has let go of them.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { malloc_zone_pressure_relief(nil, 0) }
    }

    /// Brings the window (and the Dock icon) back. Returns false when SwiftUI hasn't created the window yet.
    @discardableResult
    public static func show() -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return false }
        WindowVisibility.shared.isShown = true
        window.makeKeyAndOrderFront(nil)
        return true
    }

    /// ⌘W would really close the SwiftUI window, and with it the app; hide it instead, like the red button.
    /// Call once at launch; returns the event monitor.
    @discardableResult
    public static func interceptCloseShortcut() -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == .command, event.charactersIgnoringModifiers == "w",
                  let window = MainWindowRef.window, event.window === window else { return event }
            MainWindowRef.hide()
            return nil
        }
    }
}

/// Whether the main window is showing. While it's hidden its SwiftUI content is torn down.
public final class WindowVisibility: ObservableObject {
    public static let shared = WindowVisibility()
    @Published public var isShown = true
    /// The content's size when it was hidden; the stand-in keeps it so the window doesn't move or resize.
    var hiddenSize = CGSize(width: 1, height: 1)
}

/// Wraps a window's content so it only exists while the window is visible: views, their state and the
/// work of keeping them up to date all go away when the window is hidden, and come back when it's shown.
public struct ReleasedWhenHidden<Content: View>: View {
    @ObservedObject private var visibility = WindowVisibility.shared
    private let content: () -> Content

    public init(@ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        if visibility.isShown {
            content()
        } else {
            Color.clear.frame(width: visibility.hiddenSize.width, height: visibility.hiddenSize.height)
        }
    }
}

public struct VisualEffectBackground: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Turns the SwiftUI window into the borderless, transparent shell the design draws its own chrome in.
public struct WindowConfigurator: NSViewRepresentable {
    /// Reports the title bar height that SwiftUI reserves at the top of the window.
    public var onTitlebarInset: (CGFloat) -> Void = { _ in }

    public init(onTitlebarInset: @escaping (CGFloat) -> Void = { _ in }) {
        self.onTitlebarInset = onTitlebarInset
    }

    public func makeNSView(context: Context) -> NSView {
        let view = HostView()
        view.onTitlebarInset = onTitlebarInset
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
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
