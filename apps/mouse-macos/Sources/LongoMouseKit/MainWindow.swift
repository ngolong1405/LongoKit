import LongoKitUI
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
            ModulePanel()
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

/// Everything in the window but its frame and title bar: the tabs, the open page and the footer. The LongoKit app
/// shows it beside its sidebar.
struct ModulePanel: View {
    @EnvironmentObject private var model: AppModel
    /// The open page's height: the window fits it, up to the tallest page size.
    @State private var pageHeight = Theme.lastPageHeight

    var body: some View {
        VStack(spacing: 0) {
            TabBar(selection: $model.tab)
            // Each page gets the height it needs (taller ones scroll); the window's top edge stays put, and
            // each page starts at the top.
            SlimScrollView(contentHeight: $pageHeight, scrollTarget: model.highlighted, resetID: model.deviceSection) {
                TabContent(tab: model.tab)
            }
            .frame(height: Theme.pageHeight(pageHeight))
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

/// The main tab bar; Devices shows how many mice are connected.
struct TabBar: View {
    @EnvironmentObject private var model: AppModel
    /// In the LongoKit app, About is the app's own page.
    @Environment(\.isHosted) private var isHosted
    @Binding var selection: MainTab

    var body: some View {
        PillTabBar(tabs: isHosted ? MainTab.allCases.filter { $0 != .about } : MainTab.allCases, selection: $selection) { tab in
            tab == .devices && !model.connectedDevices.isEmpty ? L("Devices") + " (\(model.connectedDevices.count))" : tab.title
        } symbol: { tab in
            switch tab {
            case .general: return "gearshape"
            case .devices: return "computermouse"
            case .about: return "info.circle"
            }
        }
    }
}

struct WindowFooter: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.isHosted) private var isHosted
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
                // In LongoKit there's no About tab: General offers it too.
                if isHosted && tab == .general {
                    Button(action: model.copyDiagnostics) { Label(L("Copy Diagnostics"), systemImage: "doc.on.doc") }
                        .buttonStyle(.ghost)
                }
            }
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
