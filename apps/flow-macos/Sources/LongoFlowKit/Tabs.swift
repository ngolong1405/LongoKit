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

/// The desk: this Mac's displays as macOS arranges them, each paired Mac's around them where it sits, each Mac's
/// screens framed and named, and the stretches where they touch (where the pointer goes over) lit. A Mac's screens
/// follow the hand anywhere while dragged, with an outline where they'll land: against the nearest edge, sharing a
/// stretch of it, never on top of a display. Let go, they settle there, dimmed with a spinner until the Mac has it.
private struct Arrangement: View {
    @EnvironmentObject private var model: AppModel
    @State private var dragging: String?
    @State private var drag = CGSize.zero
    /// Where the Mac being dragged will land, in this Mac's points.
    @State private var landing: CGPoint?
    /// The scale and place of everything, kept while dragging and settling, so nothing jumps under the hand.
    @State private var frozen: Layout?
    static let height: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                let layout = frozen ?? Layout(local: model.localScreens, macs: model.paired.map { ($0.knownScreens, model.offset(of: $0)) },
                                              size: geometry.size)
                ZStack(alignment: .topLeading) {
                    Desk()
                    // This Mac.
                    MacFrame(rects: model.localScreens.map(layout.frame), tint: Theme.violet)
                    let biggest = Self.biggest(model.localScreens)
                    ForEach(Array(model.localScreens.enumerated()), id: \.offset) { index, screen in
                        let frame = layout.frame(screen)
                        Display(label: model.screenNames[Screens.key(screen)] ?? "\(Int(screen.width)) × \(Int(screen.height))",
                                badge: index == biggest ? MacBadge(name: model.name, status: L("This Mac"), tint: Theme.violet, live: true) : nil,
                                main: index == 0,
                                tint: Theme.violet, pointer: index == 0 && model.controlling == nil, faded: false, small: frame.width < 90)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .help(L("This Mac's displays are arranged in System Settings › Displays"))
                    }
                    // Where the pointer goes over.
                    ForEach(model.paired.filter { model.connected.contains($0.id) && dragging != $0.id }) { mac in
                        let offset = model.offset(of: mac)
                        ForEach(Array(Screens.seams(model.localScreens, mac.knownScreens.map { $0.offsetBy(dx: offset.x, dy: offset.y) }).enumerated()),
                                id: \.offset) { _, seam in
                            Seam(from: layout.point(seam.0), to: layout.point(seam.1))
                        }
                    }
                    // Where the dragged Mac will land.
                    if let dragging, let landing, let mac = model.paired.first(where: { $0.id == dragging }) {
                        ForEach(Array(mac.knownScreens.enumerated()), id: \.offset) { _, screen in
                            let frame = layout.frame(screen.offsetBy(dx: landing.x, dy: landing.y))
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Theme.emerald, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.emerald.opacity(0.1)))
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                        }
                    }
                    ForEach(model.paired) { mac in
                        group(mac, layout: layout, in: geometry.size)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .frame(height: Self.height)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))

            HStack(spacing: 14) {
                Label(model.paired.isEmpty ? L("Pair a Mac below to place it here") : L("Drag a Mac to where it sits on your desk"),
                      systemImage: "hand.draw")
                    .font(.ui(11.5, .medium))
                    .foregroundStyle(Theme.textSecondary)
                if !model.paired.isEmpty {
                    HStack(spacing: 5) {
                        Capsule().fill(Theme.solar).frame(width: 14, height: 3).shadow(color: Theme.solar.opacity(0.8), radius: 3)
                        Text(L("The pointer goes over here")).font(.ui(11)).foregroundStyle(Theme.textMuted)
                    }
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
                } label: { Label(L("Arrange this Mac's displays…"), systemImage: "display.2") }
                    .buttonStyle(GhostButtonStyle(compact: true))
            }
        }
    }

    /// The biggest display's index: its name goes there, where there's room.
    static func biggest(_ screens: [CGRect]) -> Int {
        screens.indices.max { screens[$0].width * screens[$0].height < screens[$1].width * screens[$1].height } ?? 0
    }

    /// A paired Mac: its frame and screens, dragged together, then settled (dimmed, with a spinner, until it confirms).
    @ViewBuilder private func group(_ mac: PairedMac, layout: Layout, in size: CGSize) -> some View {
        let offset = model.offset(of: mac)
        let connected = model.connected.contains(mac.id)
        let moving = dragging == mac.id ? drag : .zero
        let settling = model.placing.contains(mac.id)
        let tint = connected ? Theme.emerald : Theme.textFaint
        let frames = mac.knownScreens.map { layout.frame($0.offsetBy(dx: offset.x, dy: offset.y)).offsetBy(dx: moving.width, dy: moving.height) }
        let gesture = DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragging != mac.id {
                    frozen = layout
                    dragging = mac.id
                }
                drag = value.translation
                let moved = CGPoint(x: offset.x + value.translation.width / layout.scale, y: offset.y + value.translation.height / layout.scale)
                landing = Screens.snap(mac.knownScreens, at: moved, to: model.localScreens)
            }
            .onEnded { _ in
                let target = landing ?? offset
                // Into place smoothly, from where it was let go.
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    model.place(mac, at: target)
                    dragging = nil
                    drag = .zero
                    landing = nil
                }
                // The view settles at its new scale once the move is done.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation(.easeInOut(duration: 0.25)) { frozen = nil }
                }
            }
        Group {
            MacFrame(rects: frames, tint: tint)
            ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                Display(label: mac.knownScreens.count > 1 ? L("Display %d", index + 1) : "\(Int(mac.knownScreens[index].width)) × \(Int(mac.knownScreens[index].height))",
                        badge: index == Self.biggest(mac.knownScreens) ? MacBadge(name: mac.name, status: connected ? L("Connected") : L("Away"), tint: tint, live: connected) : nil,
                        main: index == 0, tint: tint, pointer: index == 0 && model.controlling == mac.id, faded: !connected, small: frame.width < 90)
                    .overlay {
                        if settling {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Theme.canvas.opacity(0.55))
                                .overlay(ProgressView().controlSize(.small))
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: min(max(frame.midX, 0), size.width), y: min(max(frame.midY, 0), size.height))
                    .shadow(color: .black.opacity(dragging == mac.id ? 0.3 : 0.12), radius: dragging == mac.id ? 12 : 4, y: dragging == mac.id ? 6 : 2)
                    .gesture(gesture)
                    .onHover { inside in if inside { NSCursor.openHand.push() } else { NSCursor.pop() } }
                    .help(L("Drag to where %@ sits", mac.name))
            }
        }
        .zIndex(dragging == mac.id ? 2 : 1)
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
            // Room around for the labels, and to drag a Mac to any side.
            let padded = all.insetBy(dx: -all.width * 0.2, dy: -all.height * 0.2)
            scale = min(size.width / padded.width, size.height / padded.height)
            origin = CGPoint(x: (size.width - padded.width * scale) / 2 - padded.minX * scale,
                             y: (size.height - padded.height * scale) / 2 - padded.minY * scale)
        }

        /// A display's box, a hair smaller than its place so displays side by side read as two.
        func frame(_ rect: CGRect) -> CGRect {
            CGRect(x: origin.x + rect.minX * scale + 1.5, y: origin.y + rect.minY * scale + 1.5,
                   width: max(rect.width * scale - 3, 8), height: max(rect.height * scale - 3, 6))
        }

        func point(_ point: CGPoint) -> CGPoint { CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale) }
    }
}

/// The desk under the displays: a faint dot grid.
private struct Desk: View {
    var body: some View {
        Canvas { context, size in
            let dot = GraphicsContext.Shading.color(Theme.text.opacity(0.09))
            var y: CGFloat = 8
            while y < size.height {
                var x: CGFloat = 8
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: dot)
                    x += 16
                }
                y += 16
            }
        }
        .background(Theme.tint(0.025))
    }
}

/// A Mac's screens, framed together.
private struct MacFrame: View {
    let rects: [CGRect]
    let tint: Color

    var body: some View {
        let box = rects.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -4, dy: -4)
        if !box.isNull {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(tint.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.05)))
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
                .allowsHitTesting(false)
        }
    }
}

/// A Mac's name and state, on its main display.
private struct MacBadge: View {
    let name: String
    let status: String
    let tint: Color
    let live: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "laptopcomputer").font(.system(size: 8.5, weight: .semibold))
            Text(name).font(.ui(10, .semibold)).lineLimit(1)
            Circle().fill(live ? tint : Theme.textFaint).frame(width: 6, height: 6)
        }
        .help(status)
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(Capsule().fill(Theme.island.opacity(0.92)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.5)))
    }
}

/// One display: a lit screen in its Mac's colour, its menu bar on the main one, its name, and the pointer where it is.
private struct Display: View {
    let label: String
    var badge: MacBadge? = nil
    let main: Bool
    let tint: Color
    let pointer: Bool
    let faded: Bool
    let small: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(LinearGradient(colors: [tint.opacity(0.85), tint.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
            // A soft light across the "wallpaper".
            shape.fill(RadialGradient(colors: [Color.white.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 140))
            if main {
                Rectangle().fill(Color.white.opacity(0.55)).frame(height: 4)
            }
            if let badge {
                badge.padding(.top, main ? 8 : 5).padding(.horizontal, 5)
            }
            if pointer {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !small {
                Text(label)
                    .font(.ui(9.5, .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .overlay(shape.strokeBorder(tint.opacity(0.9), lineWidth: 0.5).padding(-0.5))
        .saturation(faded ? 0.2 : 1)
        .opacity(faded ? 0.6 : 1)
        .contentShape(shape)
    }
}

/// A lit stretch of edge where two Macs' displays touch.
private struct Seam: View {
    let from: CGPoint
    let to: CGPoint

    var body: some View {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(Theme.solar, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        .shadow(color: Theme.solar.opacity(0.9), radius: 4)
        .allowsHitTesting(false)
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
