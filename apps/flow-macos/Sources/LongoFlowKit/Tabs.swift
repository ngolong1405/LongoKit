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

/// This Mac's displays as they're arranged, and each paired Mac's around them where it sits: drag a Mac's screens
/// to where it is on the desk, and they snap to the nearest edge, as in macOS's Arrange Displays.
private struct Arrangement: View {
    @EnvironmentObject private var model: AppModel
    @State private var dragging: String?
    @State private var drag = CGSize.zero
    static let height: CGFloat = 270

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.paired.isEmpty ? L("Your displays, as macOS arranges them. Paired Macs show up beside them.")
                 : L("Drag a Mac's screens to where it sits on your desk. The pointer goes over where they touch."))
                .font(.ui(11.5))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { geometry in
                let layout = Layout(local: model.localScreens, macs: model.paired.map { ($0.knownScreens, model.offset(of: $0)) },
                                    size: geometry.size)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(model.localScreens.enumerated()), id: \.offset) { index, screen in
                        Tile(title: index == 0 ? L("This Mac") : nil, main: index == 0, tint: Theme.violet,
                             pointer: index == 0 && model.controlling == nil, faded: false)
                            .frame(width: layout.size(screen).width, height: layout.size(screen).height)
                            .position(layout.center(screen))
                    }
                    ForEach(model.paired) { mac in
                        let offset = model.offset(of: mac)
                        let connected = model.connected.contains(mac.id)
                        let moving = dragging == mac.id ? drag : .zero
                        ForEach(Array(mac.knownScreens.enumerated()), id: \.offset) { index, screen in
                            let placed = screen.offsetBy(dx: offset.x, dy: offset.y)
                            Tile(title: index == 0 ? mac.name : nil, main: index == 0, tint: connected ? Theme.emerald : Theme.textFaint,
                                 pointer: index == 0 && model.controlling == mac.id, faded: !connected)
                                .frame(width: layout.size(placed).width, height: layout.size(placed).height)
                                .position(x: layout.center(placed).x + moving.width, y: layout.center(placed).y + moving.height)
                                .shadow(color: .black.opacity(dragging == mac.id ? 0.25 : 0), radius: 8, y: 4)
                                .zIndex(dragging == mac.id ? 2 : 1)
                                .gesture(DragGesture(minimumDistance: 2)
                                    .onChanged { value in
                                        dragging = mac.id
                                        drag = value.translation
                                    }
                                    .onEnded { value in
                                        let moved = CGPoint(x: offset.x + value.translation.width / layout.scale,
                                                            y: offset.y + value.translation.height / layout.scale)
                                        let snapped = Screens.snap(mac.knownScreens, at: moved, to: model.localScreens)
                                        withAnimation(Motion.quick) {
                                            model.place(mac, at: snapped)
                                            dragging = nil
                                            drag = .zero
                                        }
                                    })
                                .help(L("Drag to where %@ sits", mac.name))
                        }
                    }
                }
            }
            .frame(height: Self.height)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.tint(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
        }
    }

    /// Points on the desk to points in the box: everything fits, centred, at one scale (fixed while dragging, so a
    /// Mac doesn't run away from the pointer).
    struct Layout {
        let scale: CGFloat
        let origin: CGPoint

        init(local: [CGRect], macs: [([CGRect], CGPoint)], size: CGSize) {
            var all = local.reduce(CGRect.null) { $0.union($1) }
            for (screens, offset) in macs {
                for screen in screens { all = all.union(screen.offsetBy(dx: offset.x, dy: offset.y)) }
            }
            if all.isNull { all = CGRect(x: 0, y: 0, width: 1512, height: 982) }
            // Room around, so a Mac can be dragged to any side.
            let padded = all.insetBy(dx: -all.width * 0.25, dy: -all.height * 0.2)
            scale = min(size.width / padded.width, size.height / padded.height)
            origin = CGPoint(x: (size.width - padded.width * scale) / 2 - padded.minX * scale,
                             y: (size.height - padded.height * scale) / 2 - padded.minY * scale)
        }

        func size(_ rect: CGRect) -> CGSize { CGSize(width: max(rect.width * scale - 3, 8), height: max(rect.height * scale - 3, 6)) }
        func center(_ rect: CGRect) -> CGPoint { CGPoint(x: origin.x + rect.midX * scale, y: origin.y + rect.midY * scale) }
    }
}

/// One display in the arrangement: its menu bar on the main one, the name, and the pointer where the mouse is.
private struct Tile: View {
    let title: String?
    let main: Bool
    let tint: Color
    let pointer: Bool
    let faded: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if main {
                Rectangle().fill(Color.white.opacity(0.35)).frame(height: 4)
            }
            VStack(spacing: 4) {
                Spacer(minLength: 0)
                if pointer { Image(systemName: "cursorarrow").font(.system(size: 13, weight: .bold)).foregroundStyle(tint) }
                if let title {
                    Text(title).font(.ui(10.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1).padding(.horizontal, 4)
                }
                Spacer(minLength: 0)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(tint.opacity(0.9), lineWidth: main ? 1.6 : 1))
        .opacity(faded ? 0.55 : 1)
        .contentShape(shape)
    }
}

private struct PairedRow: View {
    @EnvironmentObject private var model: AppModel
    let mac: PairedMac

    var body: some View {
        let connected = model.connected.contains(mac.id)
        CompactRow(mac.name, help: connected ? (model.controlling == mac.id ? L("The mouse and keyboard are there now") : L("Connected")) : L("Not around now")) {
            HStack(spacing: 8) {
                Chip(connected ? L("Connected") : L("Away"), tone: connected ? .emerald : .neutral, dot: connected)
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
