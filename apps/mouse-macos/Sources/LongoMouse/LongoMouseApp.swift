import LongoKitUI
import SwiftUI

@main
struct LongoMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel(startsEngine: !Snapshot.isRequested && !SelfTest.isRequested)

    init() {
        Localizer.vietnamese = Vietnamese.strings
        // `swift run` has no app bundle, so resources come straight from Support/.
        Resource.developmentSupport = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../Support").standardized
        Fonts.register()
    }

    var body: some Scene {
        Window(AppInfo.name, id: "main") {
            MainWindow().environmentObject(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // MenuBarExtra writes isInserted back on every update; passing those no-op writes through
        // re-publishes the model, which updates the extra again and spins the main thread forever.
        MenuBarExtra(isInserted: Binding(
            get: { model.showMenuBarIcon },
            set: { if model.showMenuBarIcon != $0 { model.showMenuBarIcon = $0 } }
        )) {
            MenuPopover().environmentObject(model)
        } label: {
            Image(nsImage: Brand.menuBarImage(model.menuBarState))
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
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
        closeShortcutMonitor = MainWindowRef.interceptCloseShortcut()
    }

    /// Only Quit ends the app; closing the window leaves it running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening the app again (Finder, Spotlight, Dock) shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowRef.show() }
        return true
    }
}
