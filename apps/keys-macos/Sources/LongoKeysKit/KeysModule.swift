import LongoKitUI
import SwiftUI

/// Longo Keys as a module: what a host needs to run it.
public enum KeysModule: LongoModule {
    public static let id = "keys"
    public static let title = "Keys"
    public static let bundleIdentifier = "com.longokit.keys"
    public static var vietnamese: [String: String] { Vietnamese.strings }
    public static var resourceFolder = ""

    @MainActor public static func host(defaults: UserDefaults, live: Bool) -> any HostedModule {
        let model = AppModel(live: live, defaults: defaults)
        // About is the host's own page.
        if model.tab == .about { model.tab = .general }
        return ModelHost(model: model, panel: { ModulePanel() }, menu: { MenuPopover() },
                         isRunning: { $0.isEnabled },
                         setRunning: { $0.isEnabled = $1 },
                         prepareToQuit: { model, done in
                             model.prepareToQuit()
                             done()
                         })
    }
}

extension AppModel: HostableModel {}
