import LongoKitUI
import SwiftUI

@main
struct LongoKitApp: App {
    @NSApplicationDelegateAdaptor(KitAppDelegate.self) private var appDelegate
    @StateObject private var suite = KitAppDelegate.suite

    init() {
        // `swift run` has no app bundle, so resources come straight from Support/.
        Resource.developmentSupport = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../Support").standardized
        // LongoKit's own words first, so they win where a module words something differently.
        Localizer.register(Vietnamese.strings)
        ModuleInfo.prepareAll()
    }

    var body: some Scene {
        Window(AppInfo.name, id: "main") {
            // Torn down while the window is hidden, so the app idles in the menu bar on next to nothing.
            ReleasedWhenHidden { KitWindow().environmentObject(suite) }
                .background(WindowOpener())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Only real changes go back to the suite; MenuBarExtra writes isInserted on every update.
        MenuBarExtra(isInserted: Binding(
            get: { suite.showMenuBarIcon },
            set: { if suite.showMenuBarIcon != $0 { suite.showMenuBarIcon = $0 } }
        )) {
            KitMenu().environmentObject(suite)
        } label: {
            // A module can take over the icon, like Shot's timer while recording.
            Image(nsImage: suite.menuBarImage ?? MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Lets modules open the window when SwiftUI hasn't made it (or has dropped it).
private struct WindowOpener: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.onAppear { MainWindowRef.open = { openWindow(id: "main") } }
    }
}

final class KitAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static let suite = Suite(live: !Snapshot.isRequested && !SelfTest.isRequested)
    private var closeShortcutMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        if Snapshot.isRequested || SelfTest.isRequested {
            AppLaunch.runInBackground()
        } else if !AppLaunch.claimSingleInstance() {
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshot.isRequested { MainActor.assumeIsolated { Snapshot.renderAndExit() } }
        if SelfTest.isRequested { MainActor.assumeIsolated { SelfTest.runAndExit() } }
        MainActor.assumeIsolated {
            // Opened from the disk image: offer to move to Applications first; installed: offer to delete the installer.
            SelfInstall.check()
            Self.suite.start()
            // Right-click on the menu bar icon: Settings, each module's switch, About, Quit. Double-click: the window.
            StatusItemMenu.install(doubleClick: { MainWindowRef.show() }) { StatusMenu.make(Self.suite) }
        }
        closeShortcutMonitor = MainWindowRef.interceptCloseShortcut()
        // Started at login, the app waits in the menu bar instead of opening its window.
        if Self.launchedAtLogin {
            DispatchQueue.main.async { MainWindowRef.hide() }
        }
    }

    /// Every module finishes up before the app quits: a recording saved, displays back on, remaps cleared.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        DispatchQueue.main.async {
            Self.suite.prepareToQuit { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    /// Only Quit ends the app; closing the window leaves it running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) while it runs shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowRef.show() }
        return true
    }

    private static var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
