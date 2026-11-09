import CoreGraphics

/// Software dimming: scales the display's gamma ramp, so the picture gets darker while the backlight stays as is.
/// Works on every display, including ones without DDC; doesn't show up in screenshots.
enum Gamma {
    /// Never go fully black, so the screen stays readable even at 0.
    static let floor = 0.08

    /// 1 is untouched; lower is darker.
    static func apply(_ display: CGDirectDisplayID, factor: Double) {
        let value = Float(min(max(factor, floor), 1))
        CGSetDisplayTransferByFormula(display, 0, value, 1, 0, value, 1, 0, value, 1)
    }

    /// Puts every display back to its ColorSync profile (on quit, or when nothing is dimmed).
    static func resetAll() {
        CGDisplayRestoreColorSyncSettings()
    }
}
