import SwiftUI

/// Pick which mouse to edit; the mouse card listens for buttons; each configured button is a card of gesture rows.
/// A mouse's button layout, on its settings page.
struct ButtonsPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.editingDeviceID == nil, let id = model.activeProfileDeviceID {
                OverrideWarning(deviceID: id)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 12) {
                    MouseCard()
                    DiagnosticPanel()
                }
                .frame(width: 330)
                TriggersColumn()
            }
        }
    }
}

// MARK: - Target

/// Shown while editing the shared layout although the mouse in use has its own buttons,
/// so edits here wouldn't affect it.
private struct OverrideWarning: View {
    @EnvironmentObject private var model: AppModel
    let deviceID: String

    var body: some View {
        let name = model.displayName(deviceID)
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
            Text(L("%@ uses its own buttons, so changes here don't apply to it.", name))
                .font(.ui(12))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(L("Edit %@'s buttons", name)) { model.editingDeviceID = deviceID }
                .buttonStyle(.primary)
            Button(L("Use shared buttons")) { model.setIndependent(deviceID, false) }
                .buttonStyle(.ghost)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.amber.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.amber.opacity(0.35)))
    }
}

// MARK: - Left column

/// Mouse card: identity, illustration (also the capture field), own-buttons switch and the listen button.
private struct MouseCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var hovering = false

    var body: some View {
        let active = model.isCapturing
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Button layout")).font(.display(15, .semibold)).foregroundStyle(Theme.text)
                    Text(L("Click the mouse, then press a button to add it"))
                        .font(.ui(11))
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if active {
                    HStack(spacing: 3) {
                        Text("Esc").font(.mono(9, .semibold))
                            .padding(.horizontal, 4)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Theme.tint(0.12)))
                        Text(L("to cancel"))
                    }
                    .font(.ui(10))
                    .foregroundStyle(Theme.textMuted)
                } else {
                    OutlineTag(text: model.editingSeparateProfile ? L("Own buttons").uppercased() : L("Shared").uppercased())
                }
            }

            ZStack {
                if active { PulseRings() }
                MouseShowcase(states: buttonStates)
                    .scaleEffect(active ? 0.7 : 0.88)
            }
            .frame(height: 250)
            .frame(maxWidth: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { model.setCapturing(true) }
            .help(L("Click, then press a mouse button to add it"))

            profileRow

            Button {
                active ? model.setCapturing(false) : model.setCapturing(true)
            } label: {
                Label(active ? L("Stop listening") : L("Listen for a button"),
                      systemImage: active ? "stop.circle" : "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(active ? AnyButtonStyle(.ghost) : AnyButtonStyle(.primary))
        }
        .padding(16)
        .background(
            shape.fill(Theme.island)
                .overlay(shape.fill(LinearGradient(
                    colors: [.clear, (active ? Theme.violet : Theme.solar).opacity(0.06), Theme.violet.opacity(0.08)],
                    startPoint: .top, endPoint: .bottom)))
                .shadow(color: Theme.cardShadow, radius: 8, y: 2)
        )
        .overlay(shape.strokeBorder(active ? AnyShapeStyle(Theme.violet) : AnyShapeStyle(Theme.hairline), lineWidth: active ? 2 : 1))
        .shadow(color: Theme.violet.opacity(active ? 0.45 : hovering ? 0.12 : 0), radius: 14)
        .onHover { hovering = $0 }
        .onDisappear { model.setCapturing(false) }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: active)
    }

    @ViewBuilder private var profileRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.editingDeviceID == nil ? L("Shared button layout") : L("Use own buttons for this mouse"))
                    .font(.ui(12, .semibold))
                    .foregroundStyle(Theme.text)
                Text(model.editingDeviceID == nil ? L("Used by every mouse without its own buttons")
                                                  : L("Ignores the shared button layout"))
                    .font(.ui(10))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 0)
            if let target = model.editingDeviceID {
                DSSwitch(isOn: model.editingSeparateProfile) { model.setIndependent(target, !model.editingSeparateProfile) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.hover))
    }

    private var buttonStates: [Int: MouseShowcase.Part] {
        var states: [Int: MouseShowcase.Part] = [:]
        for binding in model.editing where binding.action != .none {
            let part: MouseShowcase.Part = binding.clickType.isPress ? .click : .gesture
            if states[binding.trigger.button] != .click { states[binding.trigger.button] = part }
        }
        return states
    }
}

private struct OutlineTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.mono(9, .semibold))
            .tracking(0.4)
            .foregroundStyle(Theme.solar)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.solar.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.solar.opacity(0.4)))
            .fixedSize()
    }
}

/// "Live input diagnostic": what the listener is doing right now.
private struct DiagnosticPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.solar)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Live input diagnostic").uppercased()).font(.mono(9)).tracking(0.4).foregroundStyle(Theme.textMuted)
                Text(line).font(.mono(11)).foregroundStyle(Theme.text).lineLimit(1)
            }
            Spacer(minLength: 6)
            if model.isCapturing {
                Chip(L("Listening"), tone: .violet, dot: true)
            } else if model.isRunning {
                Chip(L("Ready"), tone: .emerald)
            } else {
                Chip(L("Paused"), tone: .amber)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.hover))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
    }

    private var line: String {
        if model.isCapturing {
            return model.lastCapture.map { L("Added") + " " + $0 } ?? L("Listening for click / gesture…")
        }
        if let last = model.lastCapture { return L("Last") + ": " + last }
        if let id = model.activeProfileDeviceID { return L("In effect: %@'s own buttons", model.displayName(id)) }
        return L("In effect: shared buttons")
    }
}

/// Soft violet halos breathing out behind the mouse while listening.
private struct PulseRings: View {
    @State private var expand = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { ring in
                Circle()
                    .stroke(Theme.violet.opacity(0.2 - Double(ring) * 0.05), lineWidth: 6)
                    .frame(width: 130 + CGFloat(ring) * 28, height: 130 + CGFloat(ring) * 28)
                    .scaleEffect(expand ? 1.06 : 0.95)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { expand = true }
        }
    }
}

/// Top-down mouse in the app icon's solar→violet finish.
/// Configured buttons glow and get a callout label.
private struct MouseShowcase: View {
    enum Part { case click, gesture }

    /// Keyed by CG button number: 0 left, 1 right, 2 wheel, 3 rear flank, 4 front flank.
    let states: [Int: Part]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let light = scheme == .light
        let body = RoundedRectangle(cornerRadius: 66, style: .continuous)
        ZStack {
            Rectangle()
                .fill(Theme.tint(0.25))
                .frame(width: 2, height: 18)
                .offset(y: -116)
            body
                .fill(LinearGradient(colors: [Color(hex: 0xFF7A45), Color(hex: 0xD946EF), Color(hex: 0xA855F7)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    HStack(spacing: 0) {
                        Rectangle().fill(tint(0).opacity(0.4))
                        Rectangle().fill(Color.black.opacity(0.25)).frame(width: 1.5)
                        Rectangle().fill(tint(1).opacity(0.4))
                    }
                    .frame(height: 92)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipShape(body)
                )
                .overlay(body.strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5))
                .frame(width: 132, height: 214)
                .shadow(color: Color(hex: 0xD946EF).opacity(light ? 0.35 : 0.5), radius: 22, y: light ? 8 : 0)
            wheel.offset(y: -54)
            flank(button: 4, light: light).offset(x: -76, y: -6)
            flank(button: 3, light: light).offset(x: -76, y: 30)
            Circle()
                .fill(Color(hex: 0x3B1661))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.4)))
                .overlay(Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.sun))
                .frame(width: 26, height: 26)
                .offset(y: 62)
            if states[2] != nil { Callout(text: L("Wheel")).offset(x: 78, y: -74) }
            if states[4] != nil { Callout(text: "B5").offset(x: -118, y: -6) }
            if states[3] != nil { Callout(text: "B4").offset(x: -118, y: 30) }
        }
    }

    private func tint(_ button: Int) -> Color {
        switch states[button] {
        case .click: return Theme.solar
        case .gesture: return Theme.violet
        case nil: return .clear
        }
    }

    private var wheel: some View {
        let lit = states[2] != nil
        return ZStack {
            Capsule().fill(LinearGradient(colors: [Color(hex: 0xFFF4D6), Color(hex: 0xFFB070)], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 4) {
                ForEach(0..<4) { _ in Capsule().fill(Theme.solar).frame(width: 12, height: 1.5) }
            }
            Capsule().strokeBorder(Color(hex: 0x3A1A12), lineWidth: 2.5)
        }
        .frame(width: 22, height: 44)
        .shadow(color: (states[2] == .gesture ? Theme.violet : Theme.solar).opacity(lit ? 0.9 : 0), radius: 8)
    }

    private func flank(button: Int, light: Bool) -> some View {
        let color: Color = switch states[button] {
        case .click: Brand.sun
        case .gesture: Theme.violet
        case nil: light ? Color.black.opacity(0.15) : Color.white.opacity(0.25)
        }
        return Capsule()
            .fill(color)
            .frame(width: 7, height: 28)
            .shadow(color: color.opacity(states[button] == nil ? 0 : 0.8), radius: 6)
    }
}

/// Small label pointing at a configured part of the mouse.
private struct Callout: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.mono(9, .semibold))
            .foregroundStyle(Theme.solar)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.island))
            .overlay(Capsule().strokeBorder(Theme.solar.opacity(0.45)))
            .fixedSize()
    }
}

// MARK: - Right column

private struct TriggersColumn: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Configured Triggers")).font(.display(16, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Button { model.setCapturing(true) } label: { Label(L("Add New Button"), systemImage: "plus") }
                    .buttonStyle(.ghost)
            }
            if model.groups.isEmpty {
                Text(L("No buttons yet. Click the mouse on the left, then press a button to add it."))
                    .font(.ui(12))
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 14, radius: 12)
            }
            ForEach(model.groups) { ButtonCard(group: $0).transition(Motion.row) }
        }
        .animation(Motion.list, value: model.editing)
    }
}

/// One card per physical button: its name and a row per gesture.
private struct ButtonCard: View {
    @EnvironmentObject private var model: AppModel
    let group: AppModel.BindingGroup

    var body: some View {
        let unused = ClickType.allCases.filter { type in !group.rows.contains { $0.clickType == type } }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(group.trigger.title).font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                Text(group.trigger.role).font(.ui(11)).foregroundStyle(Theme.textFaint)
                Spacer()
                Button { model.removeGroup(group.trigger) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.textFaint)
                }
                .buttonStyle(.plain)
                .help(L("Remove this button"))
            }
            VStack(spacing: 4) {
                ForEach(group.rows) { GestureRow(binding: $0).transition(Motion.row) }
            }
            if !unused.isEmpty { AddGestureRow(trigger: group.trigger, types: unused) }
        }
        .card(padding: 12, radius: 12)
    }
}

/// "Single Click ········· ⊞ Mission Control"; click to change the action.
private struct GestureRow: View {
    @EnvironmentObject private var model: AppModel
    let binding: MouseBinding
    @State private var picking = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            row
            RemoveGestureButton { model.remove(binding.id) }
        }
        .id(binding.id)
    }

    @ViewBuilder private var row: some View {
        let recording = model.recording == .key(binding.id)
        let highlighted = model.highlighted == binding.id
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button { picking = true } label: {
            HStack(spacing: 8) {
                Text(binding.clickType == .click ? L("Single Click") : binding.clickType.caption)
                    .font(.mono(10))
                    .foregroundStyle(Theme.textMuted)
                Spacer(minLength: 8)
                Image(systemName: binding.action.symbol).font(.system(size: 11)).foregroundStyle(Theme.violet)
                Text(recording ? L("Press a shortcut…") : binding.actionTitle)
                    .font(.ui(12, .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.textFaint)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(shape.fill(highlighted ? Theme.violet.opacity(0.15) : hovering ? Theme.hover : Theme.segmentTrack.opacity(0.6)))
            .overlay(shape.strokeBorder(recording || highlighted || picking ? Theme.violet : Theme.hairline,
                                        lineWidth: highlighted ? 2 : 1))
            .shadow(color: Theme.violet.opacity(highlighted ? 0.5 : 0), radius: 8)
            .scaleEffect(highlighted ? 1.02 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("Click to change the action"))
        .onHover { hovering = $0 }
        .contextMenu {
            Button(L("Remove"), role: .destructive) { model.remove(binding.id) }
        }
        .popover(isPresented: $picking, arrowEdge: .trailing) {
            ActionPicker(target: .init(bindingID: binding.id, trigger: binding.trigger, clickType: binding.clickType)) {
                picking = false
            }
            .environmentObject(model)
        }
        .onChange(of: picking) { model.isPickingAction = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: highlighted)
    }
}

/// Trash button beside a gesture row; red on hover.
private struct RemoveGestureButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? Theme.danger : Theme.textMuted)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering ? Theme.danger.opacity(0.12) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(L("Remove this gesture"))
    }
}

/// Thin dashed "+ Add gesture" row. Its popover asks which gesture, then which action;
/// nothing is added if the popover is closed.
private struct AddGestureRow: View {
    @EnvironmentObject private var model: AppModel
    let trigger: Trigger
    let types: [ClickType]
    @State private var hovering = false
    @State private var picking = false
    @State private var draftType: ClickType?
    @State private var draftID = UUID()

    var body: some View {
        Button { picking = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                Text(L("Add gesture")).font(.ui(11, .medium))
            }
            .foregroundStyle(hovering || picking ? Theme.solar : Theme.textMuted)
            .padding(.leading, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $picking, arrowEdge: .trailing) {
            Group {
                if let draftType {
                    ActionPicker(target: .init(bindingID: draftID, trigger: trigger, clickType: draftType)) { picking = false }
                } else {
                    GestureTypeChooser(trigger: trigger, types: types) { draftType = $0 }
                }
            }
            .environmentObject(model)
        }
        .onChange(of: picking) { open in
            model.isPickingAction = open
            if !open {
                draftType = nil
                draftID = UUID()
            }
        }
    }
}

/// First step of adding a gesture: which kind.
private struct GestureTypeChooser: View {
    let trigger: Trigger
    let types: [ClickType]
    let choose: (ClickType) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Theme.solar).frame(width: 6, height: 6)
                Text(L("ADD GESTURE") + " · \(trigger.title.uppercased())")
                    .font(.mono(9))
                    .tracking(0.5)
                    .foregroundStyle(Theme.textMuted)
            }
            VStack(spacing: 2) {
                ForEach(types) { type in TypeRow(type: type) { choose(type) } }
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(Theme.popoverTop)
    }
}

private struct TypeRow: View {
    let type: ClickType
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(hovering ? Theme.solar : Theme.violet)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(type.title).font(.ui(12, .medium)).foregroundStyle(Theme.text)
                    Text(hint).font(.ui(10)).foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? Theme.solar : Theme.textFaint)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var symbol: String {
        switch type {
        case .click: return "cursorarrow.click"
        case .doubleClick: return "cursorarrow.click.2"
        case .hold: return "hand.tap"
        case .scroll: return "scroll"
        case .drag: return "hand.draw"
        }
    }

    private var hint: String {
        switch type {
        case .click: return L("Press once")
        case .doubleClick: return L("Press twice quickly")
        case .hold: return L("Press and hold")
        case .scroll: return L("Hold and turn the wheel")
        case .drag: return L("Hold and move the mouse")
        }
    }
}
