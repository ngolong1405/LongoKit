import AppKit
import ScreenCaptureKit

/// Takes the pictures, through ScreenCaptureKit. The app's own panels (the selection overlay, the preview, the
/// toolbars, the menu) are left out of every capture, so nothing has to be hidden first.
enum Capturer {
    enum Failure: LocalizedError {
        case notFound

        var errorDescription: String? { "The screen or window is no longer there." }
    }

    /// Whether macOS lets the app see the screen (Privacy & Security › Screen & System Audio Recording).
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks once with the system prompt; after that macOS only changes it in System Settings.
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    static func openPermissionSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Marks the panels Shot puts on screen to capture with: the selection overlay, its toolbar, the preview, the
    /// recording bar and countdown, the drawing toolbar. Only these stay out of captures.
    static let panelID = NSUserInterfaceItemIdentifier("longoshot.panel")

    /// Everything else the app shows: its settings (in LongoKit, every module's), the drawing window, the menu bar
    /// popover and its icon. Captured like any app's windows.
    @MainActor static var ownWindows: Set<CGWindowID> {
        // Menu bar icon windows report numbers past 32 bits (like 2³²) that aren't window ids: they're skipped.
        Set(NSApp.windows.filter { $0.identifier != panelID && $0.isVisible }
            .compactMap { $0.windowNumber > 0 ? CGWindowID(exactly: $0.windowNumber) : nil })
    }

    /// Every screen as it is right now, before anything of Shot's shows: picking an area then cuts from this, so menus
    /// and popovers that close at the first click are still in the picture (like macOS's own ⇧⌘4). Empty if it fails;
    /// the pick then captures live.
    @MainActor static func freeze() async -> [CGDirectDisplayID: (image: CGImage, scale: CGFloat)] {
        var frozen: [CGDirectDisplayID: (image: CGImage, scale: CGFloat)] = [:]
        for screen in NSScreen.screens {
            let scale = screen.backingScaleFactor
            if let image = try? await image(display: screen.displayID, rect: nil, scale: scale) {
                frozen[screen.displayID] = (image, scale)
            }
        }
        return frozen
    }

    /// Part of a frozen screen: `rect` in points from its top-left, `.null` for all of it.
    static func cut(_ screen: CGImage, scale: CGFloat, to rect: CGRect) -> CGImage? {
        guard !rect.isNull else { return screen }
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        return screen.cropping(to: pixels.integral)
    }

    /// Leaves the app out, but for its real windows. Panels made later, like the recording bar, stay out too.
    static func filter(_ display: SCDisplay, _ content: SCShareableContent) async -> SCContentFilter {
        let mine = content.applications.filter { $0.processID == getpid() }
        let keep = await ownWindows
        return SCContentFilter(display: display, excludingApplications: mine,
                               exceptingWindows: content.windows.filter { keep.contains($0.windowID) })
    }

    /// Part of a display, at its full pixel density. `rect` is in points from the display's top-left; nil for all of it.
    static func image(display displayID: CGDirectDisplayID, rect: CGRect?, scale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw Failure.notFound }
        let filter = await filter(display, content)
        let area = rect ?? CGRect(x: 0, y: 0, width: display.width, height: display.height)
        let config = SCStreamConfiguration()
        config.sourceRect = area
        config.width = max(1, Int((area.width * scale).rounded()))
        config.height = max(1, Int((area.height * scale).rounded()))
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// One window on its own, even if other windows cover part of it; and its pixel density. Without its shadow the
    /// picture matches the window's frame on screen exactly (to draw on it in place).
    static func image(window windowID: CGWindowID, shadow: Bool = true) async throws -> (CGImage, CGFloat) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else { throw Failure.notFound }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = max(1, Int((filter.contentRect.width * scale).rounded()))
        config.height = max(1, Int((filter.contentRect.height * scale).rounded()))
        config.showsCursor = false
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = !shadow
        return (try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config), scale)
    }

    /// Where a window is: the screen most of it is on, and its frame there in points from the screen's top-left.
    /// Nil when it doesn't fit on one screen.
    static func place(of windowID: CGWindowID) -> (NSScreen, CGRect)? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]])?.first,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
        for screen in NSScreen.screens {
            let display = CGDisplayBounds(screen.displayID)
            guard display.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
            let local = frame.offsetBy(dx: -display.minX, dy: -display.minY)
            return CGRect(origin: .zero, size: display.size).contains(local) ? (screen, local) : nil
        }
        return nil
    }

    /// The display the pointer is on.
    static func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }
}
