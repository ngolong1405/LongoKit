import LongoKitUI
import SwiftUI

/// The settings window: the modules down a sidebar, the open one's tabs and pages beside it.
struct KitWindow: View {
    @EnvironmentObject private var suite: Suite
    /// For snapshots: ImageRenderer can't draw the AppKit views (the blur, the window hookup).
    var forSnapshot = false
    /// Height of the hidden system title bar, which SwiftUI still reserves as a top safe area.
    @State private var titlebarInset: CGFloat = 0

    var body: some View {
        WindowFrame(blur: !forSnapshot, width: Sidebar.width + 1 + Theme.windowWidth) {
            TitleBar()
            HStack(alignment: .top, spacing: 0) {
                Sidebar()
                Rectangle().fill(Theme.hairline).frame(width: 1).frame(maxHeight: .infinity)
                PageView().frame(width: Theme.windowWidth)
            }
            // As tall as the open page; the sidebar stretches to match.
            .fixedSize(horizontal: false, vertical: true)
        }
        // Rebuild every view when the language changes so all L() strings update.
        .id(suite.language)
        .padding(.top, -titlebarInset)
        .background {
            if !forSnapshot { WindowConfigurator { titlebarInset = $0 } }
        }
    }
}

struct TitleBar: View {
    var body: some View {
        // The name in the middle, like a macOS settings window; window controls left, status right.
        ZStack {
            HStack(spacing: 7) {
                KitLogo(size: 20)
                Text(AppInfo.name).font(.display(14, .semibold)).tracking(-0.2).foregroundStyle(Theme.text)
            }
            HStack {
                TrafficLights()
                Spacer()
                RunningPill()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }
}

/// How many modules run, at a glance.
private struct RunningPill: View {
    @EnvironmentObject private var suite: Suite

    var body: some View {
        let running = suite.statuses.values.filter { $0 == .running || $0 == .paused }.count
        let color = running > 0 ? Theme.emerald : Theme.textFaint
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color.opacity(0.9), radius: running > 0 ? 3 : 0)
            Text(L("%d of %d on", running, ModuleInfo.all.count)).font(.ui(11, .medium)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(color.opacity(0.1)))
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    static let width: CGFloat = 184
    @EnvironmentObject private var suite: Suite

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SidebarRow(page: .general, title: L("General")) { SidebarSymbol(name: "gearshape") }
            Text(L("Modules").uppercased())
                .font(.mono(9.5, .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.textFaint)
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 4)
            ForEach(ModuleInfo.all) { info in
                let status = suite.status(info.id)
                SidebarRow(page: .module(info.id), title: info.title, status: status) {
                    ModuleLogo(info: info, size: 20, dimmed: status == .off)
                }
            }
            Spacer(minLength: 14)
            SidebarRow(page: .about, title: L("About")) { SidebarSymbol(name: "info.circle") }
        }
        // One tile behind the open page's row, sliding to the next one; the page itself changes at once.
        .backgroundPreferenceValue(SelectedRowKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let rect = proxy[anchor]
                    let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
                    shape.fill(Theme.segmentSelected)
                        .overlay(shape.strokeBorder(Theme.hairline))
                        .shadow(color: Color.black.opacity(0.1), radius: 1.5, y: 1)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            .animation(Motion.slide, value: suite.page)
        }
        .padding(10)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.chrome.opacity(0.5))
    }
}

private struct SidebarSymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textMuted)
    }
}

/// Where the open page's row is, for the tile behind it.
private struct SelectedRowKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// A page in the sidebar: its icon and name, and the module's status on the right.
private struct SidebarRow<Icon: View>: View {
    @EnvironmentObject private var suite: Suite
    let page: Suite.Page
    let title: String
    var status: Suite.Status?
    @ViewBuilder let icon: Icon
    @State private var hovering = false

    var body: some View {
        let active = suite.page == page
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Button { suite.page = page } label: {
            HStack(spacing: 10) {
                icon.frame(width: 22, height: 22)
                Text(title)
                    .font(.ui(13, active ? .semibold : .medium))
                    .foregroundStyle(active ? Theme.text : Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let status { StatusMark(status: status) }
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background {
                if hovering && !active { shape.fill(Theme.tint(0.05)) }
            }
            .anchorPreference(key: SelectedRowKey.self, value: .bounds) { active ? $0 : nil }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}

/// A module's state beside its name: a green or amber light, or an arrow while its own app runs.
struct StatusMark: View {
    let status: Suite.Status

    var body: some View {
        switch status {
        case .running: light(Theme.emerald).help(L("Running"))
        case .paused: light(Theme.amber).help(L("Paused"))
        case .elsewhere:
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.amber)
                .help(L("Open as its own app"))
        case .off: EmptyView()
        }
    }

    private func light(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 6, height: 6).shadow(color: color.opacity(0.9), radius: 3)
    }
}

// MARK: - Pages

struct PageView: View {
    @EnvironmentObject private var suite: Suite

    var body: some View {
        page.transaction { $0.animation = nil }
    }

    @ViewBuilder private var page: some View {
        switch suite.page {
        case .general: GeneralPage()
        case .about: AboutPage()
        case .module(let id):
            if let host = suite.hosts[id] {
                host.panel.id(id)
            } else if let info = ModuleInfo.named(id) {
                ModuleOffPage(info: info)
            }
        }
    }
}

/// One of LongoKit's own pages, laid out like a module's: a header where the tabs would be, the page, the footer.
struct KitPage<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content
    /// The page's height: the window fits it, up to the tallest page size.
    @State private var pageHeight = Theme.lastPageHeight

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.solar)
                Text(title).font(.display(15, .semibold)).foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(height: 52)
            .overlay(alignment: .bottom) { Hairline() }
            SlimScrollView(contentHeight: $pageHeight) { content }
                .frame(height: Theme.pageHeight(pageHeight))
            KitFooter()
        }
    }
}

struct KitFooter: View {
    var body: some View {
        HStack {
            Spacer()
            Button { NSApp.terminate(nil) } label: { Label(L("Quit"), systemImage: "power") }
                .buttonStyle(GhostButtonStyle(tint: Theme.solarLight))
                .keyboardShortcut("q")
                .help(L("Quit LongoKit: every module stops until it's opened again"))
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(Theme.chrome)
        .overlay(alignment: .top) { Hairline() }
    }
}

// MARK: - Logos

/// Small sizes use a mark: just the dark tile with a bigger glyph (Support/Marks, from brand/icons with mark=1). The full
/// logo's margins and thin lines vanish at sidebar sizes, and its light tile fades into a light window.
private let markSize: CGFloat = 40

/// LongoKit's logo; on a dark or white tile to match the appearance when large.
struct KitLogo: View {
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let image = size <= markSize ? Resource.image("Marks/Kit.png")
            : Resource.image(scheme == .dark ? "Logo.png" : "LogoLight.png") ?? Resource.image("Logo.png")
        if let logo = image {
            Image(nsImage: logo).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Theme.accentGradient)
                .overlay(Image(systemName: "square.grid.2x2.fill").font(.system(size: size * 0.45)).foregroundStyle(.white))
                .frame(width: size, height: size)
        }
    }
}

/// A module's icon; grey while it's off.
struct ModuleLogo: View {
    let info: ModuleInfo
    var size: CGFloat
    var dimmed = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let logo = size <= markSize ? Resource.image("Marks/\(info.title).png") : info.logo(dark: scheme == .dark) {
                Image(nsImage: logo).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(Theme.slate)
            }
        }
        .frame(width: size, height: size)
        .saturation(dimmed ? 0 : 1)
        .opacity(dimmed ? 0.55 : 1)
    }
}
