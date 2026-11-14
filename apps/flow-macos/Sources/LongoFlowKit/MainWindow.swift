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
    /// Every tab is this tall, so the window keeps its size; a page scrolls inside.
    static let pageHeight: CGFloat = 560

    var body: some View {
        VStack(spacing: 0) {
            TabBar()
            SlimScrollView {
                TabContent(tab: model.tab)
            }
            .frame(height: Self.pageHeight)
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
        case .devices: MacsTab()
        case .general: GeneralTab()
        case .about: AboutTab()
        }
    }
}

struct TitleBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
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

/// Where the keyboard and mouse are, at a glance.
struct StatusPill: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let color = !model.isEnabled ? Theme.textFaint : model.controlling != nil || model.controlledBy != nil ? Theme.violet
            : model.connected.isEmpty ? Theme.amber : Theme.emerald
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color.opacity(0.9), radius: 3)
            Text(model.statusText).font(.ui(11, .medium)).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(color.opacity(0.1)))
    }
}

struct TabBar: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.isHosted) private var isHosted

    var body: some View {
        PillTabBar(tabs: isHosted ? MainTab.allCases.filter { $0 != .about } : MainTab.allCases, selection: $model.tab) { tab in
            tab.title
        } symbol: { tab in
            switch tab {
            case .devices: return "laptopcomputer.and.arrow.down"
            case .general: return "gearshape"
            case .about: return "info.circle"
            }
        }
    }
}

struct WindowFooter: View {
    var body: some View {
        HStack {
            Text(L("Esc three times brings the mouse back"))
                .font(.mono(10.5))
                .foregroundStyle(Theme.textFaint)
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

/// The app mark, on a dark or white tile to match the appearance.
struct AppLogo: View {
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let logo = FlowModule.image(scheme == .dark ? "Logo.png" : "LogoLight.png") ?? FlowModule.image("Logo.png") {
            Image(nsImage: logo).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Theme.accentGradient)
                .overlay(Image(systemName: "cursorarrow.motionlines").font(.system(size: size * 0.45)).foregroundStyle(.white))
                .frame(width: size, height: size)
        }
    }
}

extension AppModel {
    var statusText: String {
        if !isEnabled { return L("Off") }
        if let controlling { return L("On %@", name(of: controlling)) }
        if let controlledBy { return L("%@ is using this Mac", name(of: controlledBy)) }
        return connected.count == 1 ? L("1 Mac connected") : L("%d Macs connected", connected.count)
    }
}
