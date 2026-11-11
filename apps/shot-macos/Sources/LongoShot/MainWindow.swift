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
            .id(model.tab)
            .transaction { $0.animation = nil }
            WindowFooter()
        }
        // Rebuild every view when the language changes so all L() strings update.
        .id(model.language)
        .padding(.top, -titlebarInset)
        .background(WindowConfigurator { titlebarInset = $0 })
        .onAppear { model.refreshPermission() }
    }
}

struct TabContent: View {
    let tab: MainTab

    var body: some View {
        switch tab {
        case .general: GeneralTab()
        case .shortcuts: ShortcutsTab()
        case .about: AboutTab()
        }
    }
}

struct TitleBar: View {
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

/// Ready, or what's missing.
struct StatusPill: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let ready = model.hasPermission
        let color = ready ? Theme.emerald : Theme.amber
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color.opacity(0.9), radius: 3)
            Text(ready ? L("Ready") : L("Needs permission")).font(.ui(11, .medium)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(color.opacity(0.1)))
        .help(ready ? L("Shortcuts are on and captures work") : L("Allow Screen Recording to capture the screen"))
    }
}

struct TabBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        PillTabBar(tabs: MainTab.allCases, selection: $model.tab) { $0.title } symbol: { tab in
            switch tab {
            case .general: return "gearshape"
            case .shortcuts: return "command.square"
            case .about: return "info.circle"
            }
        }
    }
}

struct WindowFooter: View {
    @EnvironmentObject private var model: AppModel

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
                .help(L("Quit %@: its shortcuts stop until it's opened again", AppInfo.name))
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(Theme.chrome)
        .overlay(alignment: .top) { Hairline() }
    }

    private func confirmRestore() {
        let alert = NSAlert()
        alert.messageText = L("Restore defaults?")
        alert.informativeText = L("The save folder, what happens after a capture, and every shortcut go back to the defaults.")
        alert.addButton(withTitle: L("Restore Defaults"))
        alert.addButton(withTitle: L("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { model.restoreDefaults() }
    }
}

/// The app mark: the Longo Shot icon, on a dark or white tile to match the appearance.
struct AppLogo: View {
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let logo = Resource.image(scheme == .dark ? "Logo.png" : "LogoLight.png") ?? Resource.image("Logo.png") {
            Image(nsImage: logo).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Theme.accentGradient)
                .overlay(Image(systemName: "camera.viewfinder").font(.system(size: size * 0.45)).foregroundStyle(.white))
                .frame(width: size, height: size)
        }
    }
}
