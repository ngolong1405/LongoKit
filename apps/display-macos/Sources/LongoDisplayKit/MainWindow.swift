import LongoKitUI
import SwiftUI

struct MainWindow: View {
    @EnvironmentObject private var model: AppModel
    /// Height of the hidden system title bar, which SwiftUI still reserves as a top safe area.
    @State private var titlebarInset: CGFloat = 0

    var body: some View {
        WindowFrame {
            TitleBar()
            ModulePanel()
        }
        // Rebuild every view when the language changes so all L() strings update.
        .id(model.language)
        .padding(.top, -titlebarInset)
        .background(WindowConfigurator { titlebarInset = $0 })
    }
}

/// Everything in the window but its frame and title bar: the tabs, the open page and the footer. The LongoKit app
/// shows it beside its sidebar.
struct ModulePanel: View {
    @EnvironmentObject private var model: AppModel
    /// The open page's height: the window fits it, up to the tallest page size.
    @State private var pageHeight = Theme.lastPageHeight

    var body: some View {
        VStack(spacing: 0) {
            TabBar()
            SlimScrollView(contentHeight: $pageHeight) {
                TabContent(tab: model.tab)
            }
            .frame(height: Theme.pageHeight(pageHeight))
            .id(PageID(tab: model.tab, display: model.openDisplayKey))
            .transaction { $0.animation = nil }
            WindowFooter(tab: model.tab)
        }
    }
}

private struct PageID: Hashable {
    let tab: MainTab
    let display: String?
}

struct TabContent: View {
    let tab: MainTab

    var body: some View {
        switch tab {
        case .general: GeneralTab()
        case .displays: DisplaysTab()
        case .about: AboutTab()
        }
    }
}

struct TitleBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        // The name in the middle, like a macOS settings window; window controls left, status right.
        ZStack {
            HStack(spacing: 7) {
                AppLogo(size: 22).padding(-2)
                Text(AppInfo.name).font(.display(14, .semibold)).tracking(-0.2).foregroundStyle(Theme.text)
            }
            HStack {
                TrafficLights()
                Spacer()
                ModePill()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }
}

/// Manual / Sync at a glance.
private struct ModePill: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let color = model.mode == .sync ? Theme.violet : Theme.emerald
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color.opacity(0.9), radius: 3)
            Text(model.mode.title).font(.ui(11, .medium)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(color.opacity(0.1)))
        .help(model.mode == .sync ? L("External displays follow the built-in display") : L("Each display keeps its own brightness"))
    }
}

struct TabBar: View {
    @EnvironmentObject private var model: AppModel
    /// In the LongoKit app, About is the app's own page.
    @Environment(\.isHosted) private var isHosted

    var body: some View {
        PillTabBar(tabs: isHosted ? MainTab.allCases.filter { $0 != .about } : MainTab.allCases, selection: $model.tab) { tab in
            tab == .displays && !model.displays.isEmpty ? L("Displays") + " (\(model.displays.count))" : tab.title
        } symbol: { tab in
            switch tab {
            case .general: return "gearshape"
            case .displays: return "display.2"
            case .about: return "info.circle"
            }
        }
    }
}

struct WindowFooter: View {
    @EnvironmentObject private var model: AppModel
    let tab: MainTab

    var body: some View {
        HStack {
            Button(action: confirmRestore) { Label(L("Restore Defaults"), systemImage: "arrow.counterclockwise") }
                .buttonStyle(.ghost)
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

    private func confirmRestore() {
        let alert = NSAlert()
        alert.messageText = L("Restore defaults?")
        alert.informativeText = L("Brightness, limits and dimming go back to the defaults for every display.")
        alert.addButton(withTitle: L("Restore Defaults"))
        alert.addButton(withTitle: L("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { model.restoreDefaults() }
    }
}

/// The app mark: the LongoDisplay icon, on a dark or white tile to match the appearance.
struct AppLogo: View {
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let logo = DisplayModule.image(scheme == .dark ? "Logo.png" : "LogoLight.png") ?? DisplayModule.image("Logo.png") {
            Image(nsImage: logo).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Theme.accentGradient)
                .overlay(Image(systemName: "sun.max.fill").font(.system(size: size * 0.45)).foregroundStyle(.white))
                .frame(width: size, height: size)
        }
    }
}
