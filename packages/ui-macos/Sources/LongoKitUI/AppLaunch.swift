import AppKit

/// Launch rules shared by the LongoKit apps.
public enum AppLaunch {
    /// Command-line runs (self-test, snapshots, diagnostics) work without a Dock icon or menu bar.
    public static func runInBackground() {
        NSApp.setActivationPolicy(.prohibited)
    }

    /// Only one copy of the app runs: a second launch brings the first forward and quits. Two copies would act on
    /// every event twice. Returns false when this copy should quit.
    public static func claimSingleInstance() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return true }
        let me = NSRunningApplication.current
        guard let other = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first(where: { $0 != me && !$0.isTerminated }) else { return true }
        other.activate()
        return false
    }

    /// Set by an app hosting several modules: holds a restart until nothing is under way (like a recording), then
    /// runs it.
    public static var whenIdle: ((@escaping () -> Void) -> Void)?

    /// Starts a fresh copy of the app once this one has quit, then quits (quitting lets the app finish up first).
    /// False when it can't (`swift run` has no bundle to reopen, or the helper didn't start).
    @discardableResult
    public static func relaunch() -> Bool {
        let bundle = Bundle.main.bundlePath
        guard bundle.hasSuffix(".app") else { return false }
        if let whenIdle {
            whenIdle { restart(bundle) }
            return true
        }
        return restart(bundle)
    }

    @discardableResult
    private static func restart(_ bundle: String) -> Bool {
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$0\"", bundle]
        do {
            try task.run()
            NSApp.terminate(nil)
            return true
        } catch {
            NSLog("Relaunch failed: \(error.localizedDescription)")
            return false
        }
    }
}
