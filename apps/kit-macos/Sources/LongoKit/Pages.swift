import LongoKitUI
import SwiftUI

/// The modules to turn on or off, and the settings every module shares.
struct GeneralPage: View {
    @EnvironmentObject private var suite: Suite

    var body: some View {
        KitPage(title: L("General"), symbol: "gearshape") {
            VStack(alignment: .leading, spacing: 18) {
                SettingsGroup(L("Modules")) {
                    ForEach(ModuleInfo.all) { ModuleRow(info: $0) }
                }
                AppBehaviorRows(language: $suite.language, appearance: $suite.appearance, startAtLogin: suite.startAtLogin,
                                setStartAtLogin: suite.setStartAtLogin, showMenuBarIcon: $suite.showMenuBarIcon,
                                menuBarHelp: L("Every module's quick controls, from one icon in the menu bar."))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}

/// A module: what it does, where it stands, and its switch.
private struct ModuleRow: View {
    @EnvironmentObject private var suite: Suite
    let info: ModuleInfo

    var body: some View {
        let status = suite.status(info.id)
        HStack(spacing: 12) {
            Button { suite.page = .module(info.id) } label: {
                HStack(spacing: 12) {
                    ModuleLogo(info: info, size: 30, dimmed: status == .off)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.appName).font(.ui(13, .medium)).foregroundStyle(Theme.text)
                        Text(L(info.blurb)).font(.ui(11)).foregroundStyle(Theme.textMuted).lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Open %@", info.title))
            Spacer(minLength: 8)
            switch status {
            case .running: Chip(L("Running"), tone: .emerald, dot: true)
            case .paused: Chip(L("Paused"), tone: .amber, dot: true)
            case .elsewhere:
                Button(L("Run Here")) { suite.quitOwnApp(info) }
                    .buttonStyle(GhostButtonStyle(tint: Theme.amber, compact: true))
                    .help(L("%@ is open as its own app. Quit it so LongoKit runs it instead.", info.appName))
            case .off: EmptyView()
            }
            DSSwitch(isOn: status != .off) { suite.setEnabled(info, status == .off) }
        }
        .padding(.vertical, 10)
        .settingsRow(minHeight: 58)
    }
}

/// A module that isn't running: off, or waiting for its own app to quit.
struct ModuleOffPage: View {
    @EnvironmentObject private var suite: Suite
    let info: ModuleInfo

    var body: some View {
        let elsewhere = suite.status(info.id) == .elsewhere
        KitPage(title: info.appName, symbol: elsewhere ? "arrow.up.forward.app" : "power") {
            VStack(spacing: 12) {
                ModuleLogo(info: info, size: 72, dimmed: !elsewhere)
                Text(info.appName).font(.display(22, .bold)).foregroundStyle(Theme.text)
                Text(L(info.blurb)).font(.ui(13)).foregroundStyle(Theme.textMuted)
                Text(elsewhere ? L("%@ is open as its own app. Quit it so LongoKit runs it instead.", info.appName)
                     : L("This module is off: it takes no memory and asks for no permissions."))
                    .font(.ui(12))
                    .foregroundStyle(Theme.textFaint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.top, 6)
                Group {
                    if elsewhere {
                        Button(L("Quit %@", info.appName)) { suite.quitOwnApp(info) }
                    } else {
                        Button(L("Turn On")) { suite.setEnabled(info, true) }
                    }
                }
                .buttonStyle(.primary)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 56)
            .padding(.horizontal, 24)
        }
    }
}

struct AboutPage: View {
    var body: some View {
        KitPage(title: L("About"), symbol: "info.circle") {
            VStack(spacing: 12) {
                VStack(spacing: 10) {
                    KitLogo(size: 72)
                    Text(AppInfo.name).font(.display(22, .bold)).foregroundStyle(Theme.text)
                    Chip("v\(AppInfo.version) beta", tone: .solar)
                    Text(L("Longo Mouse, Display, Keys and Shot in one menu bar app. Turn on the ones you need: the others take no memory and ask for nothing."))
                        .font(.ui(12))
                        .foregroundStyle(Theme.textMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                    HStack(spacing: 10) {
                        ForEach(ModuleInfo.all) { ModuleLogo(info: $0, size: 30).help($0.appName) }
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .panel(padding: 24)

                VStack(spacing: 0) {
                    LinkRow(symbol: "globe", title: L("Website"), detail: "longokit.vercel.app", url: AppInfo.website)
                    Hairline()
                    LinkRow(symbol: "chevron.left.forwardslash.chevron.right", title: "GitHub", detail: "ngolong1405/LongoKit", url: AppInfo.repo)
                    Hairline()
                    LinkRow(symbol: "doc.text", title: L("License"), detail: "Source-available", url: AppInfo.license)
                }
                .panel(padding: 0)
                Text(L("Crafted by %@", AppInfo.author)).font(.mono(10)).foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}

private struct LinkRow: View {
    let symbol: String
    let title: String
    let detail: String
    let url: URL

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(Theme.violet).frame(width: 22)
                Text(title).font(.ui(13, .medium)).foregroundStyle(Theme.text)
                Spacer()
                Text(detail).font(.mono(11)).foregroundStyle(Theme.textMuted)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textFaint)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
