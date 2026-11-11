import AppKit
import ScreenCaptureKit

/// Takes the pictures, through ScreenCaptureKit. The app's own windows (the selection overlay, the preview, the
/// menu) are left out of every capture, so nothing has to be hidden first.
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

    /// Part of a display, at its full pixel density. `rect` is in points from the display's top-left; nil for all of it.
    static func image(display displayID: CGDirectDisplayID, rect: CGRect?, scale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw Failure.notFound }
        let mine = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
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
