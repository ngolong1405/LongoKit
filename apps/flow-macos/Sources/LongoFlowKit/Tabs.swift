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

/// The desk, as System Settings › Displays arranges displays: this Mac's displays with their wallpapers, and each
/// paired Mac's (with theirs) where it sits. Any of them drags: one of this Mac's moves it in macOS, as there;
/// another Mac's moves that Mac. While dragged, an outline shows where it'll land (against the nearest edge, sharing
/// a stretch of it, on top of nothing); let go, it settles there, dimmed with a spinner until it's in place.
private struct Arrangement: View {
    @EnvironmentObject private var model: AppModel
    /// What's dragged: one of this Mac's displays, or another Mac.
    private enum Held: Equatable { case display(Int), mac(String) }
    @State private var held: Held?
    @State private var drag = CGSize.zero
    /// Where the dragged thing will land: a display's origin, or a Mac's offset, in this Mac's points.
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
                    // Where the dragged display or Mac will land.
                    ForEach(Array(landingFrames.enumerated()), id: \.offset) { _, rect in
                        let frame = layout.frame(rect)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.text.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.text.opacity(0.06)))
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                    // This Mac's displays.
                    let own = model.localBuiltin ?? 0
                    ForEach(Array(model.localScreens.enumerated()), id: \.offset) { index, screen in
                        let lifted = held == .display(index)
                        let frame = layout.frame(screen).offsetBy(dx: lifted ? drag.width : 0, dy: lifted ? drag.height : 0)
                        Display(wallpaper: model.wallpapers.indices.contains(index) ? model.wallpapers[index] : nil,
                                name: Self.title(Screens.short(model.screenNames[Screens.key(screen)] ?? "")),
                                badge: index == own ? MacBadge(name: model.name, status: L("This Mac"), tint: Theme.violet, live: true,
                                                               laptop: model.localBuiltin != nil) : nil,
                                main: screen.origin == .zero, tint: Theme.violet, pointer: index == own && model.controlling == nil,
                                faded: false, lifted: lifted, settling: model.arranging)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .zIndex(lifted ? 3 : 1)
                            .gesture(dragging(.display(index), layout: layout))
                            .help(model.screenNames[Screens.key(screen)] ?? "")
                    }
                    ForEach(model.paired) { mac in
                        group(mac, layout: layout)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .frame(height: Self.height)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
            Text(model.paired.isEmpty ? L("Drag displays to arrange them, as in System Settings. Paired Macs show up beside them.")
                 : L("Drag displays to arrange them, as in System Settings, and another Mac's to where it sits."))
                .font(.ui(11.5))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A display's short name to show ("Built-in" in the app's language).
    static func title(_ short: String) -> String {
        short == "Built-in" ? L("Built-in") : short
    }

    /// The outline of where the dragged thing will land.
    private var landingFrames: [CGRect] {
        guard let held, let landing else { return [] }
        switch held {
        case .display(let index):
            guard model.localScreens.indices.contains(index) else { return [] }
            return [CGRect(origin: landing, size: model.localScreens[index].size)]
        case .mac(let id):
            guard let mac = model.paired.first(where: { $0.id == id }) else { return [] }
            return mac.knownScreens.map { $0.offsetBy(dx: landing.x, dy: landing.y) }
        }
    }

    /// Dragging a display of this Mac's (against its others) or another Mac (against this Mac's displays).
    private func dragging(_ what: Held, layout: Layout) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if held != what {
                    frozen = layout
                    held = what
                }
                drag = value.translation
                let by = CGPoint(x: value.translation.width / layout.scale, y: value.translation.height / layout.scale)
                switch what {
                case .display(let index):
                    let screen = model.localScreens[index]
                    let others = model.localScreens.enumerated().filter { $0.offset != index }.map(\.element)
                    let moved = CGPoint(x: screen.minX + by.x, y: screen.minY + by.y)
                    // Several displays: against this Mac's others, as in macOS. Only one: against the other Macs'.
                    let against = others.isEmpty ? model.placedScreens() : others
                    landing = against.isEmpty ? screen.origin
                        : Screens.snap([CGRect(origin: .zero, size: screen.size)], at: moved, to: against,
                                       avoiding: others.isEmpty ? [] : model.placedScreens())
                case .mac(let id):
                    guard let mac = model.paired.first(where: { $0.id == id }) else { return }
                    let offset = model.offset(of: mac)
                    landing = Screens.snap(mac.knownScreens, at: CGPoint(x: offset.x + by.x, y: offset.y + by.y), to: model.localScreens,
                                           avoiding: model.placedScreens(except: id))
                }
            }
            .onEnded { _ in
                let target = landing
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    if let target {
                        switch what {
                        case .display(let index):
                            if model.localScreens.count == 1 {
                                model.move(display: target)
                            } else {
                                var frames = model.localScreens
                                frames[index].origin = target
                                model.arrange(frames)
                            }
                        case .mac(let id):
                            if let mac = model.paired.first(where: { $0.id == id }) { model.place(mac, at: target) }
                        }
                    }
                    held = nil
                    drag = .zero
                    landing = nil
                }
                // The view settles at its new scale once things are in place.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.easeInOut(duration: 0.25)) { frozen = nil }
                }
            }
    }

    /// A paired Mac's displays, dragged together.
    @ViewBuilder private func group(_ mac: PairedMac, layout: Layout) -> some View {
        let offset = model.offset(of: mac)
        let connected = model.connected.contains(mac.id)
        let lifted = held == .mac(mac.id)
        let own = mac.builtin ?? 0
        ForEach(Array(mac.knownScreens.enumerated()), id: \.offset) { index, screen in
            let frame = layout.frame(screen.offsetBy(dx: offset.x, dy: offset.y)).offsetBy(dx: lifted ? drag.width : 0, dy: lifted ? drag.height : 0)
            Display(wallpaper: model.theirWallpapers[mac.id]?[index],
                    name: Self.title(mac.names.indices.contains(index) ? mac.names[index] : ""),
                    badge: index == own ? MacBadge(name: mac.name, status: connected ? L("Connected") : L("Away"),
                                                   tint: connected ? Theme.emerald : Theme.textFaint, live: connected,
                                                   laptop: mac.builtin != nil || mac.screens.isEmpty) : nil,
                    main: screen.origin == .zero, tint: connected ? Theme.emerald : Theme.textFaint,
                    pointer: index == own && model.controlling == mac.id, faded: !connected, lifted: lifted,
                    settling: model.placing.contains(mac.id))
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .zIndex(lifted ? 3 : 2)
                .gesture(dragging(.mac(mac.id), layout: layout))
                .help(L("Drag to where %@ sits", mac.name))
        }
    }

    /// Points on the desk to points in the box: everything fits, centred, at one scale (fixed while dragging, so a
    /// display doesn't run away from the pointer).
    struct Layout {
        let scale: CGFloat
        let origin: CGPoint

        init(local: [CGRect], macs: [([CGRect], CGPoint)], size: CGSize) {
            var all = local.reduce(CGRect.null) { $0.union($1) }
            for (screens, offset) in macs {
                for screen in screens { all = all.union(screen.offsetBy(dx: offset.x, dy: offset.y)) }
            }
            if all.isNull { all = CGRect(x: 0, y: 0, width: 1512, height: 982) }
            // Room around, to drag a display to any side.
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

/// A Mac's name and state, on its main display.
private struct MacBadge: View {
    let name: String
    let status: String
    let tint: Color
    let live: Bool
    /// A laptop, or a desktop Mac (no display of its own).
    var laptop = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: laptop ? "laptopcomputer" : "desktopcomputer").font(.system(size: 8.5, weight: .semibold))
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

/// One display, as System Settings draws it: its wallpaper, the menu bar on the main one, and here, the Mac's name
/// on its own display and the pointer where the mouse is.
private struct Display: View {
    let wallpaper: NSImage?
    var name = ""
    var badge: MacBadge? = nil
    let main: Bool
    let tint: Color
    let pointer: Bool
    let faded: Bool
    var lifted = false
    var settling = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let shape = RoundedRectangle(cornerRadius: max(3, min(size.width, size.height) * 0.045), style: .continuous)
            ZStack(alignment: .top) {
                if let wallpaper {
                    Image(nsImage: wallpaper).resizable().interpolation(.medium).aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                } else {
                    Wallpaper(tint: tint)
                }
                if main {
                    Rectangle().fill(Color.white.opacity(0.75)).frame(height: max(3, size.height * 0.05))
                }
                if let badge {
                    badge
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.top, main ? max(7, size.height * 0.09) : 6)
                        .padding(.horizontal, 5)
                }
                if pointer {
                    Image(systemName: "cursorarrow")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if !name.isEmpty {
                    Text(name)
                        .font(.ui(size.width < 120 ? 9 : 10, .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(5)
                }
                if settling {
                    Rectangle().fill(Color.black.opacity(0.35)).overlay(ProgressView().controlSize(.small))
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(lifted ? Color.accentColor : Color.black.opacity(0.18), lineWidth: lifted ? 2 : 0.5))
            .shadow(color: .black.opacity(lifted ? 0.3 : 0.12), radius: lifted ? 12 : 3, y: lifted ? 6 : 1)
        }
        .saturation(faded ? 0.2 : 1)
        .opacity(faded ? 0.6 : 1)
        .contentShape(Rectangle())
    }
}

/// When a display's wallpaper isn't known yet: soft hills under a sky, in its Mac's colour.
private struct Wallpaper: View {
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [tint.opacity(0.55), tint.opacity(0.9)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            for (index, (top, shade)) in [(0.55, 0.25), (0.68, 0.4), (0.8, 0.55)].enumerated() {
                var hill = Path()
                hill.move(to: CGPoint(x: 0, y: h * top))
                let bumps = 3 + index
                for step in 1...bumps {
                    let x = w * CGFloat(step) / CGFloat(bumps)
                    hill.addQuadCurve(to: CGPoint(x: x, y: h * top + (step % 2 == 0 ? -h * 0.02 : h * 0.03)),
                                      control: CGPoint(x: x - w / CGFloat(bumps) / 2, y: h * (top - 0.08 * (step % 2 == 0 ? 1 : -0.4))))
                }
                hill.addLine(to: CGPoint(x: w, y: h))
                hill.addLine(to: CGPoint(x: 0, y: h))
                hill.closeSubpath()
                context.fill(hill, with: .color(Color.black.opacity(shade)))
                context.fill(hill, with: .color(tint.opacity(0.35)))
            }
        }
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
