import LongoKitUI
import SwiftUI

/// A mouse's scroll settings, on its settings page.
struct ScrollingPane: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.editingDeviceID == nil, let id = model.activeScrollDeviceID {
                ScrollOverrideWarning(deviceID: id)
            }
            if let id = model.editingDeviceID {
                SettingRow(title: L("Own scroll settings"),
                           detail: model.editingOwnScroll ? L("This mouse ignores the shared scroll settings.")
                                                          : L("Off: this mouse follows the shared scroll settings.")) {
                    DSSwitch(isOn: model.editingOwnScroll) { model.setOwnScroll(id, !model.editingOwnScroll) }
                }
                .panel()
            }
            WheelCard()
            UpcomingCard()
        }
    }
}

/// Shown while editing the shared settings although the mouse in use has its own.
private struct ScrollOverrideWarning: View {
    @EnvironmentObject private var model: AppModel
    let deviceID: String

    var body: some View {
        let name = model.displayName(deviceID)
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
            Text(L("%@ uses its own scroll settings, so changes here don't apply to it.", name))
                .font(.ui(12))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(L("Edit %@", name)) { model.editingDeviceID = deviceID }
                .buttonStyle(.primary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.amber.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.amber.opacity(0.35)))
    }
}

/// What works today: direction and speed of the mouse wheel.
private struct WheelCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let scroll = model.editingScroll
        let locked = model.editingDeviceID != nil && !model.editingOwnScroll
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(symbol: "arrow.up.arrow.down", title: L("Mouse Wheel"),
                       subtitle: L("Direction, smoothness, and speed of the wheel.")) { EmptyView() }
            if locked {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(Theme.violet)
                    Text(L("This mouse follows the shared settings below. Turn on Own scroll settings to change them just for it."))
                        .font(.ui(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .recessed(radius: 10)
            }
            Group {

            SettingRow(title: L("Scroll Direction"),
                       detail: L("Natural: the page follows the wheel, like a trackpad. Only mice change, the trackpad keeps its setting.")) {
                Segmented(options: [false, true], selection: $model.editingScroll.invertDirection,
                          title: { $0 ? L("Classic") : L("Natural") })
            }

            Hairline()

            SettingRow(title: L("Smooth Scrolling"),
                       detail: L("Each wheel notch slides the page smoothly and eases to a stop, instead of jumping.")) {
                DSSwitch(isOn: $model.editingScroll.inertia)
            }

            VStack(spacing: 8) {
                HStack {
                    Text(L("Animation Time")).font(.ui(12, .medium)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(Int((200 + 800 * scroll.smoothness).rounded())) ms").font(.mono(12, .semibold)).foregroundStyle(Theme.solar)
                }
                DSSlider(value: $model.editingScroll.smoothness, range: 0...1, step: 0.05)
                HStack {
                    Text(L("Short"))
                    Spacer()
                    Text(L("Long"))
                }
                .font(.ui(10))
                .foregroundStyle(Theme.textFaint)
            }
            .padding(12)
            .recessed(radius: 12)
            .opacity(scroll.inertia ? 1 : 0.4)
            .disabled(!scroll.inertia)

            Hairline()

            SettingRow(title: L("Custom Scroll Speed"),
                       detail: L("Changes how far each wheel notch scrolls. Hold ⌥ to slow down, ⌘ to speed up.")) {
                DSSwitch(isOn: $model.editingScroll.smoothEnabled)
            }

            VStack(spacing: 8) {
                HStack {
                    Text(L("Scroll Speed")).font(.ui(12, .medium)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(String(format: "%.2f×", scroll.speed)).font(.mono(12, .semibold)).foregroundStyle(Theme.solar)
                }
                DSSlider(value: $model.editingScroll.speed, range: ScrollSettings.speedRange, step: 0.05)
                HStack {
                    Text(L("Slow"))
                    Spacer()
                    Text(L("Default"))
                    Spacer()
                    Text(L("Fast"))
                }
                .font(.ui(10))
                .foregroundStyle(Theme.textFaint)
            }
            .padding(12)
            .recessed(radius: 12)
            .opacity(scroll.smoothEnabled ? 1 : 0.4)
            .disabled(!scroll.smoothEnabled)
            }
            .opacity(locked ? 0.5 : 1)
            .disabled(locked)
        }
        .panel()
    }
}

/// Planned scrolling features, listed so people know what's coming without controls that do nothing.
private struct UpcomingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "sparkles", title: L("Coming Later"),
                       subtitle: L("Planned scrolling features."), tint: Theme.solar) { Chip.soon }
            UpcomingRow(symbol: "gauge.with.dots.needle.67percent", title: L("Dynamic Acceleration"),
                        detail: L("Accelerates speed when the wheel is spun quickly"))
            UpcomingRow(symbol: "arrow.left.and.right", title: L("Horizontal Swipe Navigation"),
                        detail: L("Hold ⇧ Shift and scroll to go back or forward a page."))
            UpcomingRow(symbol: "plus.magnifyingglass", title: L("Screen & Canvas Zoom"),
                        detail: L("Hold ⌃ Control and scroll to zoom."))
        }
        .panel()
    }
}

private struct UpcomingRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 26, height: 26)
                .recessed(radius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(12, .medium)).foregroundStyle(Theme.textSecondary)
                Text(detail).font(.ui(11)).foregroundStyle(Theme.textMuted)
            }
            Spacer()
        }
    }
}
