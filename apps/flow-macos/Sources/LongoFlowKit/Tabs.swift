import LongoKitUI
import SwiftUI

// MARK: - Macs

/// The Macs: where each sits around this one, pairing, and the ones around to pair with.
struct MacsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.hasAccessibility {
                SettingsGroup {
                    PermissionLine(L("Accessibility"), help: L("Needed on both Macs: to take the mouse and keyboard over, and to move the pointer here."),
                                   granted: false, grant: model.askForAccessibility)
                }
            }
            PairingCard()
            Arrangement()
            SettingsGroup(L("Paired Macs")) {
                if model.paired.isEmpty {
                    CompactRow(L("None yet"), help: L("Pair with a Mac below: it shows a code to type here, once.")) { EmptyView() }
                }
                ForEach(model.paired) { mac in PairedRow(mac: mac) }
            }
            SettingsGroup(model.unpairedNearby.isEmpty ? L("Nearby") : L("Nearby (%d)", model.unpairedNearby.count)) {
                if model.unpairedNearby.isEmpty {
                    CompactRow(L("No other Macs found"), help: L("Open Longo Flow on the other Mac, on the same Wi-Fi or network.")) { EmptyView() }
                }
                ForEach(model.unpairedNearby) { mac in
                    CompactRow(mac.name) {
                        Button { model.pair(with: mac) } label: { Label(L("Pair"), systemImage: "link") }
                            .buttonStyle(PrimaryButtonStyle(compact: true))
                            .disabled(model.pairing != .none)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

/// Pairing under way: the code to type here, or the one to type on the other Mac.
private struct PairingCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var code = ""

    var body: some View {
        switch model.pairing {
        case .none:
            if let name = model.lastPaired {
                Label(L("Paired with %@. Push the pointer past the edge toward it.", name), systemImage: "checkmark.circle.fill")
                    .font(.ui(12, .medium))
                    .foregroundStyle(Theme.emerald)
            }
        case .asking(let name):
            card {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L("Asking %@…", name)).font(.ui(13, .medium)).foregroundStyle(Theme.text)
                    Spacer()
                    Button(L("Cancel"), action: model.cancelPairing).buttonStyle(GhostButtonStyle(compact: true))
                }
            }
        case .typing(let name, let wrong):
            card {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Type the code %@ shows", name)).font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                    if wrong {
                        Text(L("That wasn't it. It shows a new code now.")).font(.ui(11.5)).foregroundStyle(Theme.amber)
                    }
                    HStack(spacing: 8) {
                        CodeField(code: $code) { model.submit(code: code); code = "" }
                        Spacer()
                        Button(L("Cancel"), action: model.cancelPairing).buttonStyle(GhostButtonStyle(compact: true))
                        Button(L("Pair")) { model.submit(code: code); code = "" }
                            .buttonStyle(PrimaryButtonStyle(compact: true))
                            .disabled(code.filter(\.isNumber).count != 6)
                    }
                }
            }
        case .showing(let name, let code):
            card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("%@ wants to pair. Type this code there:", name)).font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                    Text(code.prefix(3) + " " + code.suffix(3))
                        .font(.mono(34, .bold))
                        .tracking(4)
                        .foregroundStyle(Theme.violetLight)
                    HStack {
                        Text(L("Only pair with your own Macs: a paired Mac can control this one."))
                            .font(.ui(11)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(L("Cancel"), action: model.cancelPairing).buttonStyle(GhostButtonStyle(compact: true))
                    }
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.violet.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.violet.opacity(0.5)))
    }
}

private struct CodeField: View {
    @Binding var code: String
    let submit: () -> Void
    @Environment(\.rendersFlat) private var rendersFlat

    var body: some View {
        Group {
            if rendersFlat {
                Text(code.isEmpty ? "000 000" : code).foregroundStyle(Theme.textFaint)
            } else {
                TextField("000000", text: $code).textFieldStyle(.plain).onSubmit(submit)
            }
        }
        .font(.mono(18, .semibold))
        .padding(.horizontal, 10)
        .frame(width: 130, height: 34)
        .recessed(radius: 8)
    }
}

/// This Mac in the middle, the paired ones around it where they sit.
private struct Arrangement: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let around = Dictionary(grouping: model.paired, by: \.side)
        VStack(spacing: 8) {
            slot(around[.top])
            HStack(spacing: 8) {
                slot(around[.left])
                Screen(name: model.name, state: model.controlledBy != nil ? .used : model.controlling == nil ? .here : .away, isThis: true)
                slot(around[.right])
            }
            slot(around[.bottom])
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.tint(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
    }

    @ViewBuilder private func slot(_ macs: [PairedMac]?) -> some View {
        if let mac = macs?.first {
            Screen(name: mac.name, state: !model.connected.contains(mac.id) ? .gone : model.controlling == mac.id ? .here : .ready, isThis: false)
        } else {
            Color.clear.frame(width: 120, height: 10)
        }
    }
}

private struct Screen: View {
    enum State { case here, away, used, ready, gone }
    let name: String
    let state: State
    let isThis: Bool

    var body: some View {
        let tint: Color = state == .here ? Theme.violet : state == .gone ? Theme.textFaint : state == .used ? Theme.solar : Theme.emerald
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.tint(0.06))
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tint.opacity(state == .gone ? 0.4 : 0.9), lineWidth: isThis ? 2 : 1.5)
                if state == .here {
                    Image(systemName: "cursorarrow").font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
                }
            }
            .frame(width: isThis ? 140 : 120, height: isThis ? 86 : 74)
            Text(isThis ? L("This Mac") : name).font(.ui(11, .semibold)).foregroundStyle(state == .gone ? Theme.textFaint : Theme.text).lineLimit(1)
        }
        .opacity(state == .gone ? 0.6 : 1)
    }
}

private struct PairedRow: View {
    @EnvironmentObject private var model: AppModel
    let mac: PairedMac

    var body: some View {
        let connected = model.connected.contains(mac.id)
        CompactRow(mac.name, help: connected ? (model.controlling == mac.id ? L("The mouse and keyboard are there now") : L("Connected")) : L("Not around now")) {
            HStack(spacing: 8) {
                Segmented(options: Side.allCases, selection: Binding(get: { mac.side }, set: { model.place(mac, on: $0) }), title: { $0.title })
                Button { model.unpair(mac) } label: { Image(systemName: "xmark") }
                    .buttonStyle(GhostButtonStyle(compact: true))
                    .help(L("Unpair"))
            }
        }
    }
}

// MARK: - General

struct GeneralTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            SettingsGroup(L("Status")) {
                PowerRow(name: AppInfo.name, isOn: model.isEnabled,
                         help: model.isEnabled ? L("Push the pointer past the edge toward a paired Mac to use it with this keyboard and mouse.")
                             : L("Off: the pointer stays on this Mac, and other Macs can't use it.")) {
                    model.isEnabled.toggle()
                }
            }
            SettingsGroup(L("Sharing")) {
                CompactRow(L("Share the clipboard"), help: L("What you copy goes over with the pointer: text and pictures.")) {
                    DSSwitch(isOn: $model.sharesClipboard)
                }
            }
            AppBehaviorRows(language: $model.language, appearance: $model.appearance, startAtLogin: model.startAtLogin,
                            setStartAtLogin: model.setStartAtLogin, showMenuBarIcon: $model.showMenuBarIcon,
                            menuBarHelp: L("Where the mouse is, from the menu bar."))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

// MARK: - About

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                AppLogo(size: 72)
                Text(AppInfo.name).font(.display(22, .bold)).foregroundStyle(Theme.text)
                Chip("v\(AppInfo.version) beta", tone: .solar)
                Text(L("One keyboard and mouse for your Macs: push the pointer past the edge and it's on the next Mac, with the clipboard."))
                    .font(.ui(12))
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            .frame(maxWidth: .infinity)
            .panel(padding: 24)
            Text(L("Part of LongoKit · Crafted by %@", AppInfo.author)).font(.mono(10)).foregroundStyle(Theme.textFaint)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}
