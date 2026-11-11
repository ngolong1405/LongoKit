import AppKit
import LongoKitUI
import SwiftUI

/// The brightness HUD shown when the keys change an external display: a sun and 16 segments, bottom-center
/// on that display, fading out shortly after the last press.
@MainActor
final class BrightnessOSD {
    static let shared = BrightnessOSD()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ value: Double, on displayID: CGDirectDisplayID) {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) else { return }

        let size = NSSize(width: 220, height: 64)
        let panel = self.panel ?? Self.makePanel(size: size)
        self.panel = panel
        panel.contentView = NSHostingView(rootView: OSDView(value: value))
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 120))
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel?.animator().alphaValue = 0 },
                                                 completionHandler: { panel?.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: work)
    }

    private static func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        return panel
    }
}

private struct OSDView: View {
    let value: Double

    var body: some View {
        let lit = Int((value * 16).rounded())
        HStack(spacing: 12) {
            Image(systemName: value > 0.5 ? "sun.max.fill" : "sun.min.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.solar)
                .frame(width: 22)
            HStack(spacing: 3) {
                ForEach(0..<16, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(index < lit ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.tint(0.15)))
                        .frame(width: 7, height: 14)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 220, height: 64)
        .background(VisualEffectBackground())
        .background(Theme.island)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline))
    }
}
