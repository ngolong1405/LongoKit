import SwiftUI

@main
struct LongoMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel(startsEngine: !Snapshot.isRequested && !SelfTest.isRequested)

    init() {
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
    func applicationWillFinishLaunching(_ notification: Notification) {
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshot.isRequested { MainActor.assumeIsolated { Snapshot.renderAndExit() } }
        if SelfTest.isRequested { MainActor.assumeIsolated { SelfTest.runAndExit() } }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowRef.window?.makeKeyAndOrderFront(nil) }
        return true
    }
}
