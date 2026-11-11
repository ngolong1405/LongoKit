import LongoKitUI
import SwiftUI

struct MainWindow: View {
    @EnvironmentObject private var model: AppModel
    /// Height of the hidden system title bar, which SwiftUI still reserves as a top safe area.
    @State private var titlebarInset: CGFloat = 0
    /// The open page's height: the window fits it, up to the tallest page size.
    @State private var pageHeight = Theme.contentHeight

    var body: some View {
        WindowFrame {
            TitleBar()
            TabBar()
            SlimScrollView(contentHeight: $pageHeight) {
                TabContent(tab: model.tab)
            }
            .frame(height: Theme.pageHeight(pageHeight))
            .id(PageID(tab: model.tab, keyboard: model.openKeyboard))
            .transaction { $0.animation = nil }
            // Soft blur behind an open picker keeps attention on the popover.
            .blur(radius: model.isPicking ? 3 : 0)
            .overlay(Color.black.opacity(model.isPicking ? 0.25 : 0).allowsHitTesting(false))
            .animation(.easeOut(duration: 0.2), value: model.isPicking)
            WindowFooter(tab: model.tab)
        }
        // Rebuild every view when the language changes so all L() strings update.
        .id(model.language)
        .padding(.top, -titlebarInset)
        .background(WindowConfigurator { titlebarInset = $0 })
    }
}

private struct PageID: Hashable {
    let tab: MainTab
    let keyboard: String?
}

struct TabContent: View {
    let tab: MainTab

    var body: some View {
        switch tab {
        case .general: GeneralTab()
        case .keyboards: KeyboardsTab()
        case .hyper: HyperTab()
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
                StatusPill()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }
}

/// Running / Paused at a glance (⌃⌥⌘K).
private struct StatusPill: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let color = model.isEnabled ? Theme.emerald : Theme.amber
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color.opacity(0.9), radius: 3)
            Text(model.isEnabled ? L("Running") : L("Paused")).font(.ui(11, .medium)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(color.opacity(0.1)))
        .help(L("⌃⌥⌘K pauses or resumes LongoKeys from any app."))
    }
}

struct TabBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        PillTabBar(tabs: MainTab.allCases, selection: $model.tab) { tab in
            tab == .keyboards && !model.keyboards.isEmpty ? L("Keyboards") + " (\(model.keyboards.count))" : tab.title
        } symbol: { tab in
            switch tab {
            case .general: return "gearshape"
            case .keyboards: return "keyboard"
            case .hyper: return "command.square"
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

    private func confirmRestore() {
        let alert = NSAlert()
        alert.messageText = L("Restore defaults?")
        alert.informativeText = L("Every keyboard goes back to its own keys, and the Hyper layer to its defaults.")
        alert.addButton(withTitle: L("Restore Defaults"))
        alert.addButton(withTitle: L("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { model.restoreDefaults() }
    }
}

/// The app mark: the LongoKeys icon, on a dark or white tile to match the appearance.
struct AppLogo: View {
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let logo = KeysModule.image(scheme == .dark ? "Logo.png" : "LogoLight.png") ?? KeysModule.image("Logo.png") {
            Image(nsImage: logo).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Theme.accentGradient)
                .overlay(Image(systemName: "keyboard").font(.system(size: size * 0.45)).foregroundStyle(.white))
                .frame(width: size, height: size)
        }
    }
}
