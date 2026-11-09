import LongoKitUI
import SwiftUI

@main
struct LongoDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel(live: !Snapshot.isRequested && !SelfTest.isRequested && !SelfTest.isDiagnoseRequested)

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
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.prepareToQuit()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Only real changes go back to the model; MenuBarExtra writes isInserted on every update.
        MenuBarExtra(isInserted: Binding(
            get: { model.showMenuBarIcon },
            set: { if model.showMenuBarIcon != $0 { model.showMenuBarIcon = $0 } }
        )) {
            MenuPopover().environmentObject(model)
        } label: {
            Image(systemName: "sun.max")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var closeShortcutMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshot.isRequested { MainActor.assumeIsolated { Snapshot.renderAndExit() } }
        if SelfTest.isRequested { MainActor.assumeIsolated { SelfTest.runAndExit() } }
        if SelfTest.isDiagnoseRequested { MainActor.assumeIsolated { SelfTest.diagnoseAndExit() } }
        closeShortcutMonitor = MainWindowRef.interceptCloseShortcut()
    }

    /// Only Quit ends the app; closing the window leaves it running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowRef.show() }
        return true
    }
}
