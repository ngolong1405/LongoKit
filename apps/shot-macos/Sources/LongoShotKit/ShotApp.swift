import LongoKitUI
import SwiftUI

/// The stand-alone app's window and menu bar item. Its `@main` is in the LongoShot target, so another app can host
/// this module too.
public struct ShotScenes: Scene {
    @StateObject private var model = ShotAppDelegate.model

    public init() {}

    public var body: some Scene {
        Window(AppInfo.name, id: "main") {
            // Torn down while the window is hidden, so the app waits for its shortcuts on next to nothing.
            ReleasedWhenHidden { MainWindow().environmentObject(model) }
                .background(WindowOpener(model: model))
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
            // While recording: a red center and the time, so it's clear from anywhere.
            Image(nsImage: model.isRecordingScreen
                  ? MenuBarIcon.recording(seconds: model.recordingSeconds, paused: model.isRecordingPaused) : MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Hands the model a way to open the window when SwiftUI hasn't made it (or has dropped it).
private struct WindowOpener: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.onAppear { model.openWindow = { openWindow(id: "main") } }
    }
}

public final class ShotAppDelegate: NSObject, NSApplicationDelegate {
    /// Made here so quitting can reach it to finish a recording.
    @MainActor static let model = AppModel(live: !Snapshot.isRequested && !SelfTest.isRequested && !SelfTest.isRecordTestRequested
                                               && !SelfTest.isDrawTestRequested)
    private var closeShortcutMonitor: Any?

    override public init() { super.init() }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        if SelfTest.isTextDemoRequested {
            NSApp.setActivationPolicy(.accessory)
        } else if Snapshot.isRequested || SelfTest.isRequested || SelfTest.isRecordTestRequested || SelfTest.isDrawTestRequested {
            AppLaunch.runInBackground()
        } else if !AppLaunch.claimSingleInstance() {
            exit(0)
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshot.isRequested { MainActor.assumeIsolated { Snapshot.renderAndExit() } }
        if SelfTest.isRequested { MainActor.assumeIsolated { SelfTest.runAndExit() } }
        if SelfTest.isRecordTestRequested { MainActor.assumeIsolated { SelfTest.recordAndExit() } }
        if SelfTest.isDrawTestRequested { MainActor.assumeIsolated { SelfTest.drawAndExit() } }
        if SelfTest.isTextDemoRequested { MainActor.assumeIsolated { SelfTest.textDemoAndExit() } }
        closeShortcutMonitor = MainWindowRef.interceptCloseShortcut()
        if !Snapshot.isRequested && !SelfTest.isRequested && !SelfTest.isRecordTestRequested && !SelfTest.isDrawTestRequested {
            MainActor.assumeIsolated {
                // Opened from the disk image: offer to move to Applications; installed: offer to delete the installer.
                SelfInstall.check()
                let model = Self.model
                StatusItemMenu.install(doubleClick: model.showWindow) {
                    StatusItemMenu.standard(name: AppInfo.name, icon: ShotModule.image("Logo.png"), isOn: model.isEnabled,
                                            toggle: { model.isEnabled.toggle() }, settings: model.showWindow,
                                            about: { model.tab = .about; model.showWindow() })
                }
            }
        }
        // Started at login, the app waits in the background for its shortcuts instead of opening its window.
        if Self.launchedAtLogin {
            DispatchQueue.main.async { MainWindowRef.hide() }
        }
    }

    /// A recording under way is finished and saved before the app quits.
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard Self.model.isRecordingScreen else { return .terminateNow }
            Self.model.finishRecording { NSApp.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        }
    }

    /// Only Quit ends the app; closing the window leaves it running, with its shortcuts.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) while it runs shows the window.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowRef.show() }
        return true
    }

    private static var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
