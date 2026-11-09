import LongoKitUI
import SwiftUI

/// Every connected display; picking one opens its page.
struct DisplaysTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let key = model.openDisplayKey, let display = model.displays.first(where: { $0.key == key }) {
                DisplayPage(display: display)
            } else {
                DisplayList()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

extension Display {
    /// "3840 × 2160", without locale digit grouping.
    var sizeLabel: String { "\(Int(pixelSize.width)) × \(Int(pixelSize.height))" }
}

extension ControlMethod {
    var title: String {
        switch self {
        case .native: return L("Native")
        case .ddc: return "DDC/CI"
        case .software: return L("Software")
        }
    }

    var detail: String {
        switch self {
        case .native: return L("Controlled by macOS")
        case .ddc: return L("Hardware brightness over the cable")
        case .software: return L("No DDC: dimmed in software")
        }
    }

    var tone: Chip.Tone {
        switch self {
        case .native: return .emerald
        case .ddc: return .violet
        case .software: return .amber
        }
    }
}

// MARK: - List

private struct DisplayList: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: L("Connected displays") + " (\(model.displays.count))")
            VStack(spacing: 0) {
                ForEach(Array(model.displays.enumerated()), id: \.element.key) { index, display in
                    if index > 0 { Hairline() }
                    DisplayRow(display: display)
                }
            }
            .panel(padding: 0)
            if model.externals.isEmpty {
                Text(L("Connect an external display to control its brightness."))
                    .font(.ui(12))
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel()
            }
        }
    }
}

private struct DisplayRow: View {
    @EnvironmentObject private var model: AppModel
    let display: Display

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                .font(.system(size: 16))
                .foregroundStyle(Theme.violetLight)
                .frame(width: 38, height: 38)
                .recessed(radius: 10)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.displayName(display)).font(.display(14, .semibold)).foregroundStyle(Theme.text)
                    Chip(display.method.title, tone: display.method.tone)
                }
                Text(display.sizeLabel + " · " + display.method.detail)
                    .font(.ui(11))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Text("\(Int((model.settings(for: display).brightness * 100).rounded()))%")
                .font(.mono(12, .semibold))
                .foregroundStyle(Theme.solar)
            Button { model.openDisplayKey = display.key } label: {
                HStack(spacing: 4) {
                    Text(L("Customize"))
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                }
            }
            .buttonStyle(.ghost)
        }
        .padding(14)
    }
}

// MARK: - Display page

/// One display: the screen with its brightness in the middle, minimum and maximum on either side.
private struct DisplayPage: View {
    @EnvironmentObject private var model: AppModel
    let display: Display

    var body: some View {
        let value = model.settings(for: display)
        VStack(alignment: .leading, spacing: 16) {
            Button { model.openDisplayKey = nil } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                    Text(L("Displays"))
                }
                .font(.ui(12, .medium))
                .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)

            HStack(alignment: .center, spacing: 20) {
                LimitTile(title: L("Min brightness"), value: value.minimum) { new in
                    model.update(display) { $0.minimum = min(new, $0.maximum) }
                }
                ScreenCard(display: display, value: value)
                LimitTile(title: L("Max brightness"), value: value.maximum) { new in
                    model.update(display) { $0.maximum = max(new, $0.minimum) }
                }
            }
            Text(L("In Sync mode this display moves between its minimum and maximum as the built-in display changes."))
                .font(.ui(11))
                .foregroundStyle(Theme.textMuted)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                CardHeader(symbol: "moon.fill", title: L("Extra Dimming"),
                           subtitle: L("Darker than the lowest brightness, for late nights. Done in software."),
                           tint: Theme.violet) {
                    Text("\(Int((value.extraDim * 100).rounded()))%").font(.mono(12, .semibold)).foregroundStyle(Theme.violetLight)
                }
                DSSlider(value: Binding(get: { value.extraDim },
                                        set: { new in model.update(display) { $0.extraDim = new } }),
                         range: 0...0.8, step: 0.05)
            }
            .panel()

            HStack {
                Spacer()
                Button { model.resetDisplay(display) } label: { Label(L("Reset this display"), systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.ghost)
            }
        }
    }
}

private struct ScreenCard: View {
    @EnvironmentObject private var model: AppModel
    let display: Display
    let value: DisplaySettings

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(model.displayName(display))
                    .font(.display(24, .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Chip(display.method.title, tone: display.method.tone, dot: true)
                HStack(spacing: 10) {
                    Image(systemName: "sun.min").foregroundStyle(Theme.textMuted)
                    DSSlider(value: Binding(get: { value.brightness },
                                            set: { model.setBrightness($0, for: display) }),
                             range: 0...1, step: 0.01)
                    Image(systemName: "sun.max.fill").foregroundStyle(Theme.solar)
                    Text("\(Int((value.brightness * 100).rounded()))")
                        .font(.mono(13, .semibold))
                        .foregroundStyle(Theme.solar)
                        .frame(width: 30, alignment: .trailing)
                }
                .padding(.top, 6)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.well))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.borderProminent, lineWidth: 6))
            // Stand
            Rectangle().fill(Theme.slate).frame(width: 60, height: 18)
            RoundedRectangle(cornerRadius: 3).fill(Theme.slate).frame(width: 130, height: 6)
            Text(display.sizeLabel)
                .font(.mono(11))
                .foregroundStyle(Theme.textMuted)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }
}

/// MIN / MAX: a big number with a small slider underneath.
private struct LimitTile: View {
    let title: String
    let value: Double
    let set: (Double) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("\(Int((value * 100).rounded()))")
                .font(.display(40, .bold))
                .foregroundStyle(Theme.solar)
                .frame(width: 120, height: 70)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.island))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
            Text(title.uppercased()).font(.mono(10, .semibold)).foregroundStyle(Theme.textMuted)
            DSSlider(value: Binding(get: { value }, set: set), range: 0...1, step: 0.01)
                .frame(width: 120)
        }
    }
}
