import LongoKitUI
import SwiftUI

/// Longo Shot as a module: what a host needs to run it.
public enum ShotModule: LongoModule {
    public static let id = "shot"
    public static let title = "Shot"
    public static let bundleIdentifier = "com.longokit.shot"
    public static var vietnamese: [String: String] { Vietnamese.strings }
    public static var resourceFolder = ""

    @MainActor public static func host(defaults: UserDefaults, live: Bool) -> any HostedModule {
        let model = AppModel(live: live, defaults: defaults)
        // About is the host's own page.
        if model.tab == .about { model.tab = .general }
        return ModelHost(model: model, panel: { ModulePanel() }, menu: { MenuPopover() },
                         // While recording, the menu bar shows the time.
                         menuBarImage: { $0.isRecordingScreen ? MenuBarIcon.recording(seconds: $0.recordingSeconds, paused: $0.isRecordingPaused) : nil },
                         isBusy: { $0.isRecordingScreen || $0.countdown != nil },
                         // A recording under way is finished and saved first.
                         prepareToQuit: { model, done in model.finishRecording(then: done) })
    }
}

extension AppModel: HostableModel {}
