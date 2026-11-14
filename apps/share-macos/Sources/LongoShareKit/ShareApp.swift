import LongoKitUI
import SwiftUI

/// The stand-alone app's window and menu bar item. Its `@main` is in the LongoShare target, so another app can host
/// this module too.
public struct ShareScenes: Scene {
    @StateObject private var model = ShareAppDelegate.model

    public init() {}

    public var body: some Scene {
        Window(AppInfo.name, id: "main") {
            // Torn down while the window is hidden, so the app idles in the menu bar on next to nothing.
            ReleasedWhenHidden { MainWindow().environmentObject(model) }
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
            Image(nsImage: model.isEnabled ? MenuBarIcon.image : MenuBarIcon.paused)
        }
        .menuBarExtraStyle(.window)
    }
}

public final class ShareAppDelegate: NSObject, NSApplicationDelegate {
    /// Made here so the right-click menu of the menu bar icon can reach it.
    @MainActor static let model = AppModel(live: !Snapshot.isRequested)
    private var closeShortcutMonitor: Any?

    override public init() { super.init() }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        if Snapshot.isRequested {
            AppLaunch.runInBackground()
        } else if !AppLaunch.claimSingleInstance() {
            exit(0)
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshot.isRequested { MainActor.assumeIsolated { Snapshot.renderAndExit() } }
        closeShortcutMonitor = MainWindowRef.interceptCloseShortcut()
        MainActor.assumeIsolated {
            // Opened from the disk image: offer to move to Applications; installed: offer to delete the installer.
            SelfInstall.check()
            let model = Self.model
            StatusItemMenu.install(doubleClick: { MainWindowRef.show() }) {
                StatusItemMenu.standard(name: AppInfo.name, icon: ShareModule.image("Logo.png"), isOn: model.isEnabled, toggle: { model.isEnabled.toggle() },
                                        settings: { MainWindowRef.show() },
                                        about: { model.tab = .about; MainWindowRef.show() })
            }
        }
    }

    /// Only Quit ends the app; closing the window leaves it running in the menu bar.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowRef.show() }
        return true
    }
}
