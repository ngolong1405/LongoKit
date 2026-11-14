import LongoKitUI
import SwiftUI

/// Longo Share as a module: what a host needs to run it.
public enum ShareModule: LongoModule {
    public static let id = "share"
    public static let title = "Share"
    public static let bundleIdentifier = "com.longokit.share"
    public static var vietnamese: [String: String] { Vietnamese.strings }
    public static var resourceFolder = ""

    @MainActor public static func host(defaults: UserDefaults, live: Bool) -> any HostedModule {
        let model = AppModel(live: live, defaults: defaults)
        Panels.attach(to: model)
        // About is the host's own page.
        if model.tab == .about { model.tab = .general }
        return ModelHost(model: model, panel: { ModulePanel() }, menu: { MenuPopover() },
                         isRunning: { $0.isEnabled },
                         setRunning: { $0.isEnabled = $1 },
                         isBusy: { $0.isBusy },
                         prepareToQuit: { model, done in
                             model.prepareToQuit()
                             done()
                         })
    }
}
