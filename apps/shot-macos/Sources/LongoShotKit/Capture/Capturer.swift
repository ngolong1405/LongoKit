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

    // MARK: - Instant captures

    // CoreGraphics' own screen and window captures: one synchronous call each, about 3× quicker than ScreenCaptureKit
    // (18 ms against 58 ms for a Retina screen on Apple silicon), which is what makes a shortcut feel instant. Apple
    // marks them obsolete in the macOS 15 SDK, so they're looked up at run time; if they're ever gone, or return
    // nothing, the captures go through ScreenCaptureKit instead. They need Screen Recording just the same, and keep the
    // screen's own colors.

    private typealias DisplayImage = @convention(c) (CGDirectDisplayID) -> Unmanaged<CGImage>?
    private typealias WindowImage = @convention(c) (CGRect, UInt32, CGWindowID, UInt32) -> Unmanaged<CGImage>?
    private static let coreGraphics = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
    private static let displayImage = dlsym(coreGraphics, "CGDisplayCreateImage").map { unsafeBitCast($0, to: DisplayImage.self) }
    private static let windowImage = dlsym(coreGraphics, "CGWindowListCreateImage").map { unsafeBitCast($0, to: WindowImage.self) }

    /// A whole display right now, at its pixel density, in one call; nil when that isn't available.
    static func instant(display: CGDirectDisplayID, pointWidth: CGFloat) -> (image: CGImage, scale: CGFloat)? {
        guard let image = displayImage?(display)?.takeRetainedValue(), pointWidth > 0 else { return nil }
        return (image, CGFloat(image.width) / pointWidth)
    }

    /// Whether any of Shot's own panels is on screen. CoreGraphics' captures would take them in (ScreenCaptureKit leaves
    /// them out), so then the captures go through ScreenCaptureKit.
    @MainActor static var panelsShowing: Bool {
        NSApp.windows.contains { $0.identifier == panelID && $0.isVisible && $0.alphaValue > 0 }
    }

    /// Every screen right now, before anything of Shot's shows; nil unless every one could be taken this way.
    @MainActor static func freezeNow() -> [CGDirectDisplayID: (image: CGImage, scale: CGFloat)]? {
        guard !panelsShowing else { return nil }
        var frozen: [CGDirectDisplayID: (image: CGImage, scale: CGFloat)] = [:]
        for screen in NSScreen.screens {
            guard let still = instant(display: screen.displayID, pointWidth: screen.frame.width) else { return nil }
            frozen[screen.displayID] = still
        }
        return frozen
    }

    /// One window on its own, in one call; nil when that isn't available. Only that window is taken, so whatever is
    /// over it (the selection overlay too) stays out.
    @MainActor static func instant(window: CGWindowID, shadow: Bool) -> (CGImage, CGFloat)? {
        // kCGWindowListOptionIncludingWindow; kCGWindowImageBestResolution, plus BoundsIgnoreFraming without the shadow.
        let options: UInt32 = 1 << 3 | (shadow ? 0 : 1 << 0)
        guard let image = windowImage?(.null, 1 << 3, window, options)?.takeRetainedValue(), image.width > 1 else { return nil }
        // The shadow makes the picture larger than the window: the density comes from the screen it's on.
        let scale = place(of: window)?.0.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return (image, scale)
    }

    /// Every screen as it is right now, before anything of Shot's shows: picking an area then cuts from this, so menus
    /// and popovers that close at the first click are still in the picture (like macOS's own ⇧⌘4). Empty if it fails;
    /// the pick then captures live.
    @MainActor static func freeze() async -> [CGDirectDisplayID: (image: CGImage, scale: CGFloat)] {
        let screens = NSScreen.screens.map { ($0.displayID, $0.backingScaleFactor) }
        // What's on screen, asked once for every screen; then every screen at once.
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return [:] }
        return await withTaskGroup(of: (CGDirectDisplayID, CGImage, CGFloat)?.self) { group in
            for (display, scale) in screens {
                group.addTask {
                    guard let image = try? await image(display: display, rect: nil, scale: scale, content: content) else { return nil }
                    return (display, image, scale)
                }
            }
            var frozen: [CGDirectDisplayID: (image: CGImage, scale: CGFloat)] = [:]
            for await case let (display, image, scale)? in group { frozen[display] = (image, scale) }
            return frozen
        }
    }

    /// The display's own colors (Display P3 on a Mac's screen), so a capture looks like the screen did, and the frozen
    /// screen under the selection overlay matches the live one exactly. ScreenCaptureKit gives sRGB otherwise.
    static func colorSpace(of display: CGDirectDisplayID) -> CFString {
        let space = CGDisplayCopyColorSpace(display)
        if let name = space.name, name == CGColorSpace.displayP3 || name == CGColorSpace.sRGB { return name }
        return space.isWideGamutRGB ? CGColorSpace.displayP3 : CGColorSpace.sRGB
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
    /// `content`: what's on screen, when already at hand (asking macOS for it is the slow part of a capture).
    static func image(display displayID: CGDirectDisplayID, rect: CGRect?, scale: CGFloat,
                      content known: SCShareableContent? = nil) async throws -> CGImage {
        let content: SCShareableContent
        if let known { content = known } else { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw Failure.notFound }
        let filter = await filter(display, content)
        let area = rect ?? CGRect(x: 0, y: 0, width: display.width, height: display.height)
        let config = SCStreamConfiguration()
        config.sourceRect = area
        config.width = max(1, Int((area.width * scale).rounded()))
        config.height = max(1, Int((area.height * scale).rounded()))
        config.showsCursor = false
        config.captureResolution = .best
        config.colorSpaceName = colorSpace(of: displayID)
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
        config.colorSpaceName = colorSpace(of: CGMainDisplayID())
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
