import Carbon.HIToolbox
import LongoKitUI
import SwiftUI

/// Every keyboard; picking one (or "All keyboards") opens its page.
struct KeyboardsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let id = model.openKeyboard, id == AppModel.allKeyboards || model.keyboard(id) != nil {
                KeyboardPage(id: id)
            } else {
                KeyboardList()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

extension CapsMode {
    var title: String {
        switch self {
        case .unchanged: return L("Unchanged")
        case .escape: return "Esc"
        case .control: return "⌃ Control"
        case .hyper: return "Hyper"
        }
    }

    var detail: String {
        switch self {
        case .unchanged: return L("Caps Lock works as usual.")
        case .escape: return L("Caps Lock is a second Esc.")
        case .control: return L("Caps Lock is a Control key, easier to reach.")
        case .hyper: return L("Tap: Esc. Hold: Hyper (⌃⌥⇧⌘) and the Hyper layer.")
        }
    }
}

// MARK: - List

private struct KeyboardList: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AllKeyboardsRow().panel(padding: 0)

            SectionLabel(text: L("Connected keyboards") + " (\(model.keyboards.count))")
            VStack(spacing: 0) {
                ForEach(Array(model.keyboards.enumerated()), id: \.element.id) { index, keyboard in
                    if index > 0 { Hairline() }
                    KeyboardRow(keyboard: keyboard)
                }
                if model.keyboards.isEmpty {
                    Text(L("No keyboard found.")).font(.ui(12)).foregroundStyle(Theme.textMuted).padding(14)
                }
            }
            .panel(padding: 0)

            KeyTester()
        }
    }
}

/// The shared settings: what every keyboard without its own uses.
private struct AllKeyboardsRow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            RowIcon(symbol: "square.stack.3d.up.fill", on: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(L("All keyboards")).font(.display(14, .semibold)).foregroundStyle(Theme.text)
                Text(L("Shared settings, used by every keyboard without its own")).font(.ui(11)).foregroundStyle(Theme.textMuted)
            }
            Spacer()
            ProfileBadges(profile: model.shared)
            CustomizeButton { model.openKeyboard = AppModel.allKeyboards }
        }
        .padding(14)
    }
}

/// A connected keyboard: on/off, what it does at a glance, and Caps Lock right here.
private struct KeyboardRow: View {
    @EnvironmentObject private var model: AppModel
    let keyboard: KeyboardDevice

    var body: some View {
        let on = model.isOn(keyboard.id)
        let own = model.hasOwnSettings(keyboard.id)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RowIcon(symbol: keyboard.symbol, on: on)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName(keyboard)).font(.display(14, .semibold))
                        .foregroundStyle(on ? Theme.text : Theme.textMuted)
                    Text(L(keyboard.connection)).font(.ui(11)).foregroundStyle(Theme.textMuted)
                }
                Spacer()
                if !on {
                    Text(L("Types as usual")).font(.ui(10)).foregroundStyle(Theme.textFaint)
                } else if own {
                    ProfileBadges(profile: model.profile(for: keyboard.id))
                } else {
                    Text(L("Shared settings")).font(.ui(10)).foregroundStyle(Theme.textFaint)
                }
                DSSwitch(isOn: on) { model.setOn(keyboard.id, !on) }
                    .scaleEffect(0.8)
                    .frame(width: 32, height: 18)
                    .help(on ? L("Turn off: this keyboard types as usual") : L("Turn on"))
                CustomizeButton { model.openKeyboard = keyboard.id }
            }
            if on {
                HStack(spacing: 10) {
                    Text(L("Caps Lock")).font(.ui(11)).foregroundStyle(Theme.textSecondary)
                    Segmented(options: CapsMode.allCases,
                              selection: Binding(get: { model.profile(for: keyboard.id).caps },
                                                 set: { new in model.change(own ? keyboard.id : nil) { $0.caps = new } }),
                              title: { $0.title }, stretch: true)
                }
                .padding(.leading, 50)
                .help(own ? "" : L("Changes the shared settings, for every keyboard without its own."))
            }
        }
        .padding(14)
    }
}

private struct RowIcon: View {
    let symbol: String
    let on: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16))
            .foregroundStyle(on ? Theme.violetLight : Theme.textFaint)
            .frame(width: 38, height: 38)
            .recessed(radius: 10)
    }
}

/// "Caps → Hyper" and "3 remaps", or a faint "No changes".
private struct ProfileBadges: View {
    let profile: KeyboardProfile

    var body: some View {
        HStack(spacing: 4) {
            if profile.caps != .unchanged { Chip("Caps → " + profile.caps.title, tone: profile.caps == .hyper ? .solar : .violet) }
            if !profile.remaps.isEmpty { Chip(L("%d remaps", profile.remaps.count)) }
            if profile == KeyboardProfile() { Text(L("No changes")).font(.ui(10)).foregroundStyle(Theme.textFaint) }
        }
    }
}

private struct CustomizeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(L("Customize"))
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
            }
        }
        .buttonStyle(.ghost)
    }
}

/// Press keys to see what reaches apps, lit up on a keyboard: the remapped key, with Hyper when it's held.
private struct KeyTester: View {
    @EnvironmentObject private var model: AppModel
    @State private var listening = false
    @State private var pressed: Set<Key> = []
    @State private var hyper = false
    @State private var last = ""
    @State private var monitor: Any?
    /// Drives the "listening" glow.
    @State private var pulse = false

    /// Modifier keys by key code, to light the right side.
    private static let modifierKeys: [UInt16: (Key, NSEvent.ModifierFlags)] = [
        UInt16(kVK_Control): (.leftControl, .control), UInt16(kVK_RightControl): (.rightControl, .control),
        UInt16(kVK_Option): (.leftOption, .option), UInt16(kVK_RightOption): (.rightOption, .option),
        UInt16(kVK_Shift): (.leftShift, .shift), UInt16(kVK_RightShift): (.rightShift, .shift),
        UInt16(kVK_Command): (.leftCommand, .command), UInt16(kVK_RightCommand): (.rightCommand, .command),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: listening ? "ear.fill" : "ear", title: L("Try your keys"),
                       subtitle: listening ? L("Listening: the keys you type show up here and don't reach other apps.")
                                           : L("Shows what apps receive, after remaps and Hyper."),
                       tint: listening ? Theme.solar : Theme.violet) {
                HStack(spacing: 10) {
                    if listening {
                        HStack(spacing: 6) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                                .shadow(color: .red, radius: pulse ? 5 : 1)
                                .opacity(pulse ? 1 : 0.35)
                            Text(L("LISTENING")).font(.mono(10, .bold)).foregroundStyle(Theme.solar)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(Theme.solar.opacity(0.12)))
                    }
                    Button(listening ? L("Stop") : L("Listen")) { listening ? stop() : start() }
                        .buttonStyle(listening ? AnyButtonStyle(.primary) : AnyButtonStyle(.ghost))
                }
            }
            HStack(spacing: 8) {
                Circle().fill(listening ? Theme.emerald : Theme.textFaint).frame(width: 7, height: 7)
                Text(last.isEmpty ? (listening ? L("Press any key…") : L("Click Listen, then press keys.")) : last)
                    .font(.mono(12, .semibold)).foregroundStyle(last.isEmpty ? Theme.textMuted : Theme.text)
                Spacer()
                if hyper { Chip("Hyper", tone: .solar, dot: true) }
            }
            TesterKeyboard(pressed: pressed, hyper: hyper)
                .opacity(listening ? 1 : 0.55)
            if listening && !HyperTap.shared.isRunning {
                Text(L("The top row's brightness, media and volume keys need Accessibility permission (General tab) to show here."))
                    .font(.ui(11)).foregroundStyle(Theme.amber)
            }
        }
        .panel()
        // While listening the card glows, so it's clear keys are being caught.
        .overlay {
            if listening {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.accentGradient, lineWidth: 2)
                    .shadow(color: Theme.solar.opacity(pulse ? 0.55 : 0.1), radius: pulse ? 14 : 4)
                    .opacity(pulse ? 1 : 0.45)
                    .allowsHitTesting(false)
            }
        }
        .onDisappear(perform: stop)
        // Switching to another app stops listening, so the top row's keys work there.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in stop() }
    }

    private func start() {
        listening = true
        pulse = false
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        // The top row's system keys never reach the window; the Hyper tap catches them while listening.
        HyperTap.shared.listener = { fKey, action, down in
            let key = Key(usage: 0x3A + UInt32(fKey - 1))
            if down {
                pressed.insert(key)
                last = "\(key.name) · \(L(action))   ·   " + L("kept from macOS while listening")
            } else {
                pressed.remove(key)
            }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            hyper = flags == [.control, .option, .shift, .command]
            switch event.type {
            case .flagsChanged:
                if let (key, flag) = Self.modifierKeys[event.keyCode] {
                    // Hyper's modifiers come with keys, not from held modifier keys: only light real presses.
                    if event.modifierFlags.contains(flag) { pressed.insert(key) } else { pressed.remove(key) }
                }
                return event
            case .keyDown:
                let key = Key.usage(forKeyCode: Int(event.keyCode))
                if let key { pressed.insert(key) }
                last = (hyper ? "Hyper + " : Self.symbols(flags)) + (key?.name ?? "#\(event.keyCode)") + "   ·   code \(event.keyCode)"
                return nil
            case .keyUp:
                if let key = Key.usage(forKeyCode: Int(event.keyCode)) { pressed.remove(key) }
                return nil
            default:
                return event
            }
        }
    }

    private func stop() {
        HyperTap.shared.listener = nil
        listening = false
        withAnimation(.easeOut(duration: 0.2)) { pulse = false }
        pressed = []
        hyper = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func symbols(_ flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s.isEmpty ? "" : s + " "
    }
}

/// The keyboard picture for the tester: keys light up while they're down; Caps Lock lights as the Hyper key.
private struct TesterKeyboard: View {
    let pressed: Set<Key>
    let hyper: Bool

    var body: some View {
        VStack(spacing: 5) {
            ForEach(Array(KeyboardLayout.rows.enumerated()), id: \.offset) { _, row in
                GeometryReader { geometry in
                    let unit = (geometry.size.width - CGFloat(row.count - 1) * 5) / CGFloat(row.reduce(0) { $0 + $1.width })
                    HStack(spacing: 5) {
                        ForEach(row) { cap in
                            let lit = cap.key.map(pressed.contains) ?? false
                            let hyperKey = hyper && cap.key == .capsLock
                            Text(hyperKey ? "Hyper" : cap.label)
                                .font(.ui(10, lit || hyperKey ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.6)
                                .foregroundStyle(lit || hyperKey ? Color.white : (cap.key == nil ? Theme.textFaint : Theme.text))
                                .frame(width: unit * cap.width, height: 30)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(lit ? AnyShapeStyle(Theme.accentGradient)
                                          : hyperKey ? AnyShapeStyle(Theme.solar) : AnyShapeStyle(Theme.tint(0.06))))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.hairline))
                                .shadow(color: Theme.solar.opacity(lit ? 0.6 : 0), radius: 6)
                                .scaleEffect(lit ? 0.94 : 1)
                                .animation(.easeOut(duration: lit ? 0.05 : 0.25), value: lit)
                        }
                    }
                }
                .frame(height: 30)
            }
        }
        .padding(12)
        .recessed(radius: 12)
    }
}

/// A ButtonStyle chosen at runtime.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

// MARK: - Keyboard page

private struct KeyboardPage: View {
    @EnvironmentObject private var model: AppModel
    let id: String

    var body: some View {
        let keyboard = model.keyboard(id)
        let isAll = id == AppModel.allKeyboards
        let editable = isAll || model.hasOwnSettings(id)
        VStack(alignment: .leading, spacing: 16) {
            Button { model.openKeyboard = nil } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                    Text(L("Keyboards"))
                }
                .font(.ui(12, .medium))
                .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)

            HStack(spacing: 14) {
                GlyphTile(tint: Theme.violet, size: 44) {
                    Image(systemName: isAll ? "square.stack.3d.up.fill" : keyboard?.symbol ?? "keyboard")
                        .font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.violet)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(isAll ? L("All keyboards") : keyboard.map(model.displayName) ?? "").font(.display(20, .bold)).foregroundStyle(Theme.text)
                    Text(isAll ? L("Shared settings, used by every keyboard without its own") : keyboard.map { L($0.connection) } ?? "")
                        .font(.ui(12)).foregroundStyle(Theme.textMuted)
                }
                Spacer()
                if !isAll {
                    VStack(alignment: .trailing, spacing: 4) {
                        DSSwitch(isOn: model.hasOwnSettings(id)) { model.setOwnSettings(id, !model.hasOwnSettings(id)) }
                        Text(L("Own settings")).font(.mono(10, .semibold)).foregroundStyle(Theme.textFaint)
                    }
                }
            }
            .panel()

            Group {
                CapsCard(id: id)
                RemapsCard(id: id)
            }
            .disabled(!editable)
            .opacity(editable ? 1 : 0.5)
            if !editable {
                Text(L("This keyboard uses the shared settings. Turn on Own settings to change them just for it."))
                    .font(.ui(12)).foregroundStyle(Theme.textMuted)
            }
        }
    }
}

private struct CapsCard: View {
    @EnvironmentObject private var model: AppModel
    let id: String

    var body: some View {
        let caps = model.profile(for: id).caps
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "capslock", title: L("Caps Lock"), subtitle: caps.detail, tint: Theme.solar) { EmptyView() }
            Segmented(options: CapsMode.allCases, selection: Binding(get: { caps }, set: { mode in model.change(id) { $0.caps = mode } }),
                      title: { $0.title }, stretch: true)
            if caps == .hyper && !model.hasAccessibility {
                Text(L("Hyper needs Accessibility permission (General tab); until then Caps Lock stays as it is."))
                    .font(.ui(11)).foregroundStyle(Theme.amber)
            }
        }
        .panel()
    }
}

/// The keyboard picture: click a key to choose what it sends.
private struct RemapsCard: View {
    @EnvironmentObject private var model: AppModel
    let id: String

    var body: some View {
        let profile = model.profile(for: id)
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "keyboard", title: L("Remap keys"),
                       subtitle: L("Click a key to choose what it sends. Works everywhere, even in password fields."),
                       tint: Theme.violet) {
                Button(profile.swapsCommandOption ? L("Unswap ⌘ ⌥") : L("Swap ⌘ ⌥")) {
                    model.change(id) { p in
                        if p.swapsCommandOption {
                            p.remaps.removeAll { KeyboardProfile.swapCommandOption.contains($0) }
                        } else {
                            p.remaps.removeAll { r in KeyboardProfile.swapCommandOption.contains { $0.from == r.from } }
                            p.remaps += KeyboardProfile.swapCommandOption
                        }
                    }
                }
                .buttonStyle(.ghost)
                .help(L("For keyboards made for Windows, where ⊞ and Alt sit the other way round."))
            }
            KeyboardPicture(id: id)
            if !profile.remaps.isEmpty {
                VStack(spacing: 6) {
                    ForEach(profile.remaps, id: \.self) { remap in
                        HStack(spacing: 8) {
                            Text(remap.from.name).font(.mono(12, .semibold)).foregroundStyle(Theme.text)
                            Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textFaint)
                            Text(remap.to.name).font(.mono(12, .semibold)).foregroundStyle(Theme.solar)
                            Spacer()
                            Button { model.change(id) { $0.remaps.removeAll { $0 == remap } } } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.textMuted)
                            .help(L("Remove"))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .recessed(radius: 8)
                    }
                }
            }
        }
        .panel()
    }
}

private struct KeyboardPicture: View {
    @EnvironmentObject private var model: AppModel
    let id: String

    var body: some View {
        VStack(spacing: 5) {
            ForEach(Array(KeyboardLayout.rows.enumerated()), id: \.offset) { _, row in
                GeometryReader { geometry in
                    let unit = (geometry.size.width - CGFloat(row.count - 1) * 5) / CGFloat(row.reduce(0) { $0 + $1.width })
                    HStack(spacing: 5) {
                        ForEach(row) { cap in
                            KeyCapButton(id: id, cap: cap).frame(width: unit * cap.width)
                        }
                    }
                }
                .frame(height: 32)
            }
        }
        .padding(12)
        .recessed(radius: 12)
    }
}

private struct KeyCapButton: View {
    @EnvironmentObject private var model: AppModel
    let id: String
    let cap: KeyboardLayout.Cap
    @State private var picking = false

    var body: some View {
        let profile = model.profile(for: id)
        let target = cap.key.flatMap(profile.target)
        let isCaps = cap.key == .capsLock && profile.caps != .unchanged
        let changed = target != nil || isCaps
        Button { if cap.key != nil && cap.key != .capsLock { picking = true } } label: {
            VStack(spacing: 1) {
                Text(cap.label).font(.ui(10, .medium)).lineLimit(1).minimumScaleFactor(0.6)
                if let target {
                    Text("→ " + target.name).font(.mono(8, .bold)).lineLimit(1).minimumScaleFactor(0.5)
                } else if isCaps {
                    Text("→ " + profile.caps.title).font(.mono(8, .bold)).lineLimit(1).minimumScaleFactor(0.5)
                }
            }
            .foregroundStyle(changed ? Color.white : (cap.key == nil ? Theme.textFaint : Theme.text))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(changed ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.tint(0.06))))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(cap.key == nil)
        .help(cap.key == .capsLock ? L("Set Caps Lock in the card above.") : "")
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            if let key = cap.key {
                TargetPicker(key: key, current: target) { new in
                    picking = false
                    model.change(id) { p in
                        p.remaps.removeAll { $0.from == key }
                        if let new, new != key { p.remaps.append(Remap(from: key, to: new)) }
                    }
                } dismiss: { picking = false }
            }
        }
        .onChange(of: picking) { model.isPicking = $0 }
    }
}
