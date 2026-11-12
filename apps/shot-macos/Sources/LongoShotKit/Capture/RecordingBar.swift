import AppKit
import LongoKitUI
import SwiftUI

/// What shows while recording: a bar at the bottom of the screen with the time, Pause and Stop, and a dashed outline
/// around the area being recorded. Both are the app's own windows, so they never end up in the video.
@MainActor
final class RecordingBar {
    private var bar: NSPanel?
    private var outline: NSPanel?

    func show(on screen: NSScreen, area: CGRect?, model: AppModel) {
        hide()
        // Sized once here: the timer and the pulsing dot change inside a bar that stays the same size.
        let (host, size) = fixedHostingView(BarView().environmentObject(model))
        let visible = screen.visibleFrame
        // Bottom center, just above the Dock, where it's easy to find and out of the way of menus.
        let panel = Self.panel(CGRect(x: visible.midX - size.width / 2, y: visible.minY + 12,
                                      width: size.width, height: size.height))
        panel.contentView = host
        panel.isMovableByWindowBackground = true
        panel.orderFrontRegardless()
        bar = panel

        // The area is in points from the screen's top-left; panels are placed from the bottom-left.
        if let area {
            let frame = CGRect(x: screen.frame.minX + area.minX - 3, y: screen.frame.maxY - area.maxY - 3,
                               width: area.width + 6, height: area.height + 6)
            let outline = Self.panel(frame)
            outline.ignoresMouseEvents = true
            outline.contentView = OutlineView(frame: CGRect(origin: .zero, size: frame.size))
            outline.orderFrontRegardless()
            self.outline = outline
        }
    }

    /// The bar's size on screen (zero when hidden), for the recording test.
    var size: CGSize { bar?.frame.size ?? .zero }

    func hide() {
        bar?.orderOut(nil)
        outline?.orderOut(nil)
        bar = nil
        outline = nil
    }

    private static func panel(_ frame: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.identifier = Capturer.panelID
        // Up and gone at once: no zoom from macOS.
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    private struct BarView: View {
        @EnvironmentObject private var model: AppModel
        @State private var pulse = false
        @State private var hoveringStop = false
        @State private var hoveringPause = false

        var body: some View {
            let paused = model.isRecordingPaused
            let accent = paused ? Theme.amber : Theme.danger
            HStack(spacing: 14) {
                // Red and pulsing while recording; amber and still while paused.
                ZStack {
                    Circle().fill(accent.opacity(0.25)).frame(width: 26, height: 26).scaleEffect(paused || !pulse ? 0.7 : 1)
                    Circle().fill(accent).frame(width: 12, height: 12).shadow(color: accent, radius: 6)
                }
                .frame(width: 26, height: 26)
                .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { pulse = true } }
                // Fixed widths, so the bar doesn't change size as the time grows or it's paused.
                VStack(alignment: .leading, spacing: 1) {
                    Text(paused ? L("Paused") : L("Recording"))
                        .font(.ui(11, .semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                    Text(RecordingBar.time(model.recordingSeconds))
                        .font(.mono(19, .bold))
                        .foregroundStyle(Color.white)
                        .monospacedDigit()
                }
                .frame(width: 92, alignment: .leading)
                Button { model.perform(.pauseRecording) } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white.opacity(hoveringPause ? 0.3 : 0.16)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { hoveringPause = $0 }
                .help(pauseHelp(paused))
                Button { model.perform(.record) } label: {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2.5).fill(Color.white).frame(width: 12, height: 12)
                        Text(L("Stop")).font(.ui(14, .semibold)).foregroundColor(.white).fixedSize()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(Capsule().fill(Theme.danger.opacity(hoveringStop ? 1 : 0.88))
                        .shadow(color: Theme.danger.opacity(0.6), radius: hoveringStop ? 10 : 5))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hoveringStop = $0 }
                .help(model.shortcuts[.record].map { L("Stop recording (%@)", $0.symbols) } ?? L("Stop recording"))
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 56)
            .background(Capsule().fill(Color(hex: 0x111216).opacity(0.94)))
            .overlay(Capsule().strokeBorder(accent.opacity(0.75), lineWidth: 1.5))
            .shadow(color: accent.opacity(0.45), radius: 14)
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            // Room for the glow and the shadow inside the panel.
            .padding(18)
        }

        private func pauseHelp(_ paused: Bool) -> String {
            let title = paused ? L("Resume recording") : L("Pause recording")
            return model.shortcuts[.pauseRecording].map { "\(title) (\($0.symbols))" } ?? title
        }
    }

    /// The bar on its own, for snapshots.
    static var preview: some View { BarView() }

    /// "0:07", "12:41", "1:02:03".
    static func time(_ seconds: Int) -> String {
        let h = seconds / 3600, m = seconds / 60 % 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private final class OutlineView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 2
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.systemRed.withAlphaComponent(0.85).setStroke()
        path.stroke()
    }
}

/// 3, 2, 1 in the middle of what's about to be recorded. Esc (or the record shortcut again) cancels.
@MainActor
final class CountdownPanel {
    private var panel: NSPanel?

    func show(on screen: NSScreen, area: CGRect?, model: AppModel) {
        hide()
        let (host, size) = fixedHostingView(CountdownView().environmentObject(model))
        // Centered on the area (top-left points on the screen), or on the screen.
        let center = area.map { CGPoint(x: screen.frame.minX + $0.midX, y: screen.frame.maxY - $0.midY) }
            ?? CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        let panel = KeyPanel(contentRect: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                                 width: size.width, height: size.height),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.identifier = Capturer.panelID
        // Up and gone at once: no zoom from macOS.
        panel.animationBehavior = .none
        // The record shortcut during the countdown cancels it; so does Esc.
        panel.onEscape = { [weak model] in model?.perform(.record) }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = host
        // Key, without bringing the app forward, so it hears Esc.
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    var size: CGSize { panel?.frame.size ?? .zero }

    private final class KeyPanel: NSPanel {
        var onEscape: () -> Void = {}

        override var canBecomeKey: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { onEscape() } else { super.keyDown(with: event) }
        }

        override func cancelOperation(_ sender: Any?) { onEscape() }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private struct CountdownView: View {
        @EnvironmentObject private var model: AppModel

        var body: some View {
            VStack(spacing: 10) {
                Text("\(model.countdown ?? 0)")
                    .font(.display(64, .bold))
                    .foregroundStyle(Color.white)
                    .monospacedDigit()
                    .frame(width: 128, height: 128)
                    .background(Circle().fill(Color.black.opacity(0.72)))
                    .overlay(Circle().strokeBorder(Theme.danger.opacity(0.9), lineWidth: 3))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: model.countdown)
                Text(L("Recording starts soon · Esc cancels"))
                    .font(.ui(12, .medium))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.72)))
                    .fixedSize()
            }
            .padding(12)
            .frame(width: 300)
        }
    }
}

/// Under an area picked for recording: the whole screen instead, sound and microphone, Cancel and Start.
struct RecordToolbar: View {
    @EnvironmentObject private var model: AppModel
    let send: (SelectionOverlay.Command) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ToolbarButton(symbol: "display", title: L("Whole Screen"), help: L("Record the whole screen instead")) {
                send(.wholeScreen)
            }
            divider
            ToolbarToggle(on: model.recordSystemAudio, symbol: "speaker.wave.2.fill", offSymbol: "speaker.slash.fill",
                          help: L("Record the Mac's sound")) { model.recordSystemAudio.toggle() }
            ToolbarToggle(on: model.recordMicrophone && AppModel.canRecordMicrophone, symbol: "mic.fill", offSymbol: "mic.slash.fill",
                          help: AppModel.canRecordMicrophone ? L("Record the microphone") : L("Needs macOS 15 or later.")) {
                model.recordMicrophone.toggle()
            }
            .disabled(!AppModel.canRecordMicrophone)
            divider
            ToolbarButton(symbol: nil, title: L("Cancel"), help: L("Esc")) { send(.cancel) }
            Button { send(.start) } label: {
                HStack(spacing: 7) {
                    Circle().fill(Color.white).frame(width: 10, height: 10)
                    Text(L("Start Recording")).font(.ui(13, .semibold)).foregroundColor(.white).fixedSize()
                    Text("↩").font(.mono(11, .semibold)).foregroundColor(.white.opacity(0.7)).fixedSize()
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Capsule().fill(Theme.danger).shadow(color: Theme.danger.opacity(0.55), radius: 6))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(L("Start recording this area"))
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0x111216).opacity(0.95)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        .padding(14)
        .environment(\.colorScheme, .dark)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 24)
    }
}

private struct ToolbarButton: View {
    let symbol: String?
    let title: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.ui(12, .medium)).fixedSize()
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(Color.white.opacity(hovering ? 0.18 : 0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// An icon that's bright when on and struck through when off.
private struct ToolbarToggle: View {
    let on: Bool
    let symbol: String
    let offSymbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: on ? symbol : offSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(on ? .white : .white.opacity(0.45))
                .frame(width: 36, height: 36)
                .background(Circle().fill(on ? Theme.danger.opacity(0.3) : Color.white.opacity(hovering ? 0.16 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .help(help + " · " + (on ? L("On") : L("Off")))
    }
}
