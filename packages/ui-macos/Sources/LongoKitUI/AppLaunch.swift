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
}
