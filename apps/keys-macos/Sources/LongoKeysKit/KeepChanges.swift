import AppKit
import LongoKitUI

/// After keys change: "Keep these keys?", like macOS asks after a resolution change. With no answer the change is
/// undone by itself, so a remap that leaves you unable to type the answer fixes itself.
enum KeepChanges {
    static let seconds = 15

    @MainActor
    static func ask() -> Bool {
        let alert = NSAlert()
        alert.messageText = L("Keep these keys?")
        func update(_ left: Int) {
            alert.informativeText = L("Try a few keys. Your keys go back to how they were in %d seconds unless you keep them.", left)
                + "\n\n" + L("⌃⌥⌘K pauses LongoKeys at any time.")
        }
        update(seconds)
        alert.addButton(withTitle: L("Keep"))
        alert.addButton(withTitle: L("Undo"))
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
