import AppKit
import LongoKitUI

/// After a display is turned off: "Keep it off?", like macOS asks after a resolution change. With no answer the
/// display comes back on by itself, so turning off the wrong screen (or one whose neighbour shows nothing) fixes
/// itself.
enum PowerConfirmation {
    static let seconds = 15

    /// Whether to keep the display off.
    @MainActor
    static func keepOff(name: String, blackout: Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = L("Keep %@ off?", name)
        let detail = blackout
            ? L("macOS wouldn't turn it off, so its picture is black instead.") + " "
            : ""
        func update(_ left: Int) {
            alert.informativeText = detail + L("It turns back on in %d seconds unless you keep it off.", left)
                + "\n\n" + L("⌃⌥⌘B turns every display back on at any time.")
        }
        update(seconds)
        alert.addButton(withTitle: L("Keep Off"))
        alert.addButton(withTitle: L("Turn On Now"))

        var left = seconds
        let timer = Timer(timeInterval: 1, repeats: true) { timer in
            left -= 1
            if left <= 0 {
                timer.invalidate()
                NSApp.abortModal()
            } else {
                MainActor.assumeIsolated { update(left) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        timer.invalidate()
        return response == .alertFirstButtonReturn
    }
}
