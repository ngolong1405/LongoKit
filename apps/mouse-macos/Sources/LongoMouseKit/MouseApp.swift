import LongoKitUI
import SwiftUI

/// The stand-alone app's window and menu bar item. Its `@main` is in the LongoMouse target, so another app can host
/// this module too.
public struct MouseScenes: Scene {
    @StateObject private var model = MouseAppDelegate.model

    public init() {}

    public var body: some Scene {
        Window(AppInfo.name, id: "main") {
            // Torn down while the window is hidden, so the app idles in the menu bar on next to nothing.
            ReleasedWhenHidden { MainWindow().environmentObject(model) }
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
            Image(nsImage: model.isEnabled ? Brand.menuBarImage(model.menuBarState) : Brand.pausedMenuBarImage)
        }
        .menuBarExtraStyle(.window)
    }
}

public final class MouseAppDelegate: NSObject, NSApplicationDelegate {
    /// Made here so the right-click menu of the menu bar icon can reach it.
    @MainActor static let model = AppModel(startsEngine: !Snapshot.isRequested && !SelfTest.isRequested)
    private var closeShortcutMonitor: Any?

    override public init() { super.init() }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        if Snapshot.isRequested || SelfTest.isRequested {
            AppLaunch.runInBackground()
        } else if !AppLaunch.claimSingleInstance() {
            exit(0)
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshot.isRequested { MainActor.assumeIsolated { Snapshot.renderAndExit() } }
        if SelfTest.isRequested { MainActor.assumeIsolated { SelfTest.runAndExit() } }
        closeShortcutMonitor = MainWindowRef.interceptCloseShortcut()
        if !Snapshot.isRequested && !SelfTest.isRequested {
            MainActor.assumeIsolated {
                let model = Self.model
                StatusItemMenu.install(doubleClick: { MainWindowRef.show() }) {
                    StatusItemMenu.standard(name: AppInfo.name, icon: MouseModule.image("Logo.png"), isOn: model.isRunning, toggle: model.toggleEnabled,
                                            settings: { MainWindowRef.show() },
                                            about: { model.tab = .about; MainWindowRef.show() })
                }
            }
        }
    }

    /// Only Quit ends the app; closing the window leaves it running in the menu bar.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening the app again (Finder, Spotlight, Dock) shows the window.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowRef.show() }
        return true
    }
}
