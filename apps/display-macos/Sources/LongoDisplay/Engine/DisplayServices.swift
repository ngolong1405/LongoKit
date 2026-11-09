import CoreGraphics
import Foundation

/// Brightness of the built-in display and Apple displays (Studio Display, Pro Display XDR), through Apple's
/// private DisplayServices framework. Loaded at runtime so a missing symbol degrades instead of crashing.
enum DisplayServices {
    private typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static let canChangeFn = symbol("DisplayServicesCanChangeBrightness", as: CanChange.self)
    private static let getFn = symbol("DisplayServicesGetBrightness", as: GetBrightness.self)
    private static let setFn = symbol("DisplayServicesSetBrightness", as: SetBrightness.self)

    static func canChangeBrightness(_ display: CGDirectDisplayID) -> Bool {
        canChangeFn?(display) ?? false
    }

    /// 0…1, or nil when the display doesn't report it.
    static func brightness(_ display: CGDirectDisplayID) -> Double? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(display, &value) == 0 ? Double(value) : nil
    }

    @discardableResult
    static func setBrightness(_ display: CGDirectDisplayID, _ value: Double) -> Bool {
        guard let setFn else { return false }
        return setFn(display, Float(min(max(value, 0), 1))) == 0
    }
}
