import CoreGraphics
import Foundation

/// Turns a display off and on as if its cable were unplugged: windows move to the other displays.
///
/// Safety comes first:
/// - Changes are made "for this app only" (`.forAppOnly`): if Longo Display quits, crashes or is force-quit,
///   macOS itself turns every display back on. A display can't be left off by a broken app.
/// - The last display that's on can never be turned off.
/// - Only displays this app turned off are ever turned on again; it never touches a closed MacBook lid.
/// - ⌃⌥⌘B turns every display back on, from anywhere, without any permission (see `AppModel`).
enum DisplayPower {
    private typealias ConfigureEnabled = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    /// From SkyLight, the private framework under CoreGraphics; looked up at runtime so a missing symbol only
    /// disables the feature.
    private static let configureEnabled: ConfigureEnabled? = {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        guard let symbol = dlsym(handle, "CGSConfigureDisplayEnabled") else { return nil }
        return unsafeBitCast(symbol, to: ConfigureEnabled.self)
    }()

    static var isAvailable: Bool { configureEnabled != nil }

    /// Displays macOS is showing a picture on right now.
    static func activeCount() -> Int {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        return Int(count)
    }

    /// Whether turning this display off keeps at least one display on.
    static func canTurnOff(_ display: CGDirectDisplayID) -> Bool {
        isAvailable && CGDisplayIsActive(display) != 0 && activeCount() > 1
    }

    /// Turns a display off or on. Returns whether macOS accepted the change.
    @discardableResult
    static func set(_ display: CGDirectDisplayID, on: Bool) -> Bool {
        guard let configureEnabled else { return false }
        if !on && !canTurnOff(display) { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        guard configureEnabled(config, display, on) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .forAppOnly) == .success
    }

    /// Connected displays macOS isn't showing a picture on (turned off, or a closed MacBook lid).
    static func inactiveOnline() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).filter { CGDisplayIsActive($0) == 0 }
    }
}
