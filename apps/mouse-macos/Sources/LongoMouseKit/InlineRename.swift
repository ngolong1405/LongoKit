import AppKit
import LongoKitUI
import SwiftUI

/// A device name that turns into a text field in place, with Save and Cancel, when its edit icon is clicked.
struct InlineRename: View {
    @EnvironmentObject private var model: AppModel
    let deviceID: String
    var font: Font = .display(14, .semibold)
    var color: Color = Theme.text

    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var frame: CGRect = .zero
    @State private var clickMonitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            if editing {
                Group {
                TextField(model.profiles[deviceID]?.product ?? "", text: $text)
                    .textFieldStyle(.plain)
                    .font(font)
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 110, maxWidth: 220, minHeight: 24, maxHeight: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.segmentTrack))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.solar.opacity(0.7)))
                    .focused($focused)
                    .onSubmit(save)
                    .onExitCommand(perform: cancel)
                Button(L("Save"), action: save).buttonStyle(PrimaryButtonStyle(compact: true))
                Button(L("Cancel"), action: cancel).buttonStyle(GhostButtonStyle(compact: true))
                }
                .transition(.opacity)
            } else {
                Text(model.displayName(deviceID)).font(font).foregroundStyle(color).lineLimit(1)
                Button(action: begin) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.solar)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.solar.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.solar.opacity(0.3)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Rename this mouse"))
            }
        }
        // Same height whether showing the name or the field, so nothing below shifts.
        .frame(height: 26)
        .animation(Motion.quick, value: editing)
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { frame = geometry.frame(in: .global) }
                .onChange(of: geometry.frame(in: .global)) { frame = $0 }
        })
        // Leaving the field (tabbing away, switching apps, closing the page) ends editing without saving.
        .onChange(of: focused) { isFocused in
            if !isFocused && editing { cancel() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if editing { cancel() }
        }
        .onDisappear(perform: stopWatchingClicks)
    }

    private func begin() {
        text = model.displayName(deviceID)
        editing = true
        DispatchQueue.main.async { focused = true }
        watchClicks()
    }

    /// Clicking empty parts of the window doesn't take focus from a text field, so clicks outside
    /// the field and its buttons are watched for directly.
    private func watchClicks() {
        stopWatchingClicks()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            if let content = event.window?.contentView {
                let point = content.convert(event.locationInWindow, from: nil)
                let flipped = content.isFlipped ? point : CGPoint(x: point.x, y: content.bounds.height - point.y)
                if !frame.insetBy(dx: -4, dy: -4).contains(flipped) { cancel() }
            }
            return event
        }
    }

    private func stopWatchingClicks() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    private func save() {
        let name = text.trimmingCharacters(in: .whitespaces)
        // Saving the original product name (or nothing) goes back to the default name.
        model.setNickname(deviceID, name == model.profiles[deviceID]?.product ? nil : name)
        editing = false
        stopWatchingClicks()
    }

    private func cancel() {
        editing = false
        stopWatchingClicks()
    }
}
