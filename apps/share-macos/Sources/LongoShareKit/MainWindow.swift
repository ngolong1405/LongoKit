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
    var body: some View {
        VStack(spacing: 0) {
            TabBar()
            // Every tab is the chat's height, so the window stays put; the chat scrolls its own parts, the other
            // pages scroll as a whole. The page swaps at once: no fade of one over the other.
            Group {
                if model.tab == .devices {
                    DevicesTab()
                } else {
                    SlimScrollView {
                        TabContent(tab: model.tab)
                    }
                }
            }
            .frame(height: DevicesTab.height)
            .id(model.tab)
            .transition(.identity)
            .transaction { $0.animation = nil }
            WindowFooter()
        }
    }
}

struct TabContent: View {
    let tab: MainTab

    var body: some View {
        switch tab {
        case .devices: DevicesTab()
        case .general: GeneralTab()
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

/// How many devices are around, at a glance.
private struct StatusPill: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let color = !model.isEnabled ? Theme.textFaint : model.peers.isEmpty ? Theme.amber : Theme.emerald
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color.opacity(0.9), radius: 3)
            Text(model.statusText).font(.ui(11, .medium)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(color.opacity(0.1)))
    }
}

struct TabBar: View {
    @EnvironmentObject private var model: AppModel
    /// In the LongoKit app, About is the app's own page.
    @Environment(\.isHosted) private var isHosted

    var body: some View {
        PillTabBar(tabs: isHosted ? MainTab.allCases.filter { $0 != .about } : MainTab.allCases, selection: $model.tab) { tab in
            tab == .devices && model.unread > 0 ? L("Devices") + " (\(model.unread))" : tab.title
        } symbol: { tab in
            switch tab {
            case .devices: return "bubble.left.and.bubble.right"
            case .general: return "gearshape"
            case .about: return "info.circle"
            }
        }
    }
}

struct WindowFooter: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack {
            Button { NSWorkspace.shared.open(model.folder) } label: { Label(L("Open Received Files"), systemImage: "folder") }
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
}

/// The app mark: the Longo Share icon, on a dark or white tile to match the appearance.
struct AppLogo: View {
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let logo = ShareModule.image(scheme == .dark ? "Logo.png" : "LogoLight.png") ?? ShareModule.image("Logo.png") {
            Image(nsImage: logo).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Theme.accentGradient)
                .overlay(Image(systemName: "arrow.left.arrow.right").font(.system(size: size * 0.45)).foregroundStyle(.white))
                .frame(width: size, height: size)
        }
    }
}

extension AppModel {
    /// "3 devices", "Off".
    var statusText: String {
        if !isEnabled { return L("Off") }
        if let current { return "\(Int(current.fraction * 100))%" }
        return peers.count == 1 ? L("1 device") : L("%d devices", peers.count)
    }
}
