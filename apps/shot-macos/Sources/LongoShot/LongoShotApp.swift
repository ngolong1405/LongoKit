import LongoKitUI
import SwiftUI

@main
struct LongoShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppDelegate.model

    init() {
        Localizer.vietnamese = Vietnamese.strings
        // `swift run` has no app bundle, so resources come straight from Support/.
        Resource.developmentSupport = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../Support").standardized
        Fonts.register()
    }

    var body: some Scene {
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Made here so quitting can reach it to finish a recording.
    @MainActor static let model = AppModel(live: !Snapshot.isRequested && !SelfTest.isRequested && !SelfTest.isRecordTestRequested
                                               && !SelfTest.isDrawTestRequested)
    private var closeShortcutMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        if Snapshot.isRequested || SelfTest.isRequested || SelfTest.isRecordTestRequested || SelfTest.isDrawTestRequested {
            AppLaunch.runInBackground()
        } else if !AppLaunch.claimSingleInstance() {
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Snapshot.isRequested { MainActor.assumeIsolated { Snapshot.renderAndExit() } }
        if SelfTest.isRequested { MainActor.assumeIsolated { SelfTest.runAndExit() } }
        if SelfTest.isRecordTestRequested { MainActor.assumeIsolated { SelfTest.recordAndExit() } }
        if SelfTest.isDrawTestRequested { MainActor.assumeIsolated { SelfTest.drawAndExit() } }
        closeShortcutMonitor = MainWindowRef.interceptCloseShortcut()
        // Started at login, the app waits in the background for its shortcuts instead of opening its window.
        if Self.launchedAtLogin {
            DispatchQueue.main.async { MainWindowRef.hide() }
        }
    }

    /// A recording under way is finished and saved before the app quits.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard Self.model.isRecordingScreen else { return .terminateNow }
            Self.model.finishRecording { NSApp.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        }
    }

    /// Only Quit ends the app; closing the window leaves it running, with its shortcuts.
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
