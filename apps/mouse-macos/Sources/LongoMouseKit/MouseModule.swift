import LongoKitUI
import SwiftUI

/// Longo Mouse as a module: what a host needs to run it.
public enum MouseModule: LongoModule {
    public static let id = "mouse"
    public static let title = "Mouse"
    public static let bundleIdentifier = "com.longngo.MouseMapper"
    public static var vietnamese: [String: String] { Vietnamese.strings }
    public static var resourceFolder = ""

    public static func prepare() {
        prepareShared()
        AppModel.noteLaunch()
    }

    @MainActor public static func host(defaults: UserDefaults, live: Bool) -> any HostedModule {
        let model = AppModel(startsEngine: live, defaults: defaults)
        // About is the host's own page.
        if model.tab == .about { model.tab = .general }
        return ModelHost(model: model, panel: { ModulePanel() }, menu: { MenuPopover() },
                         isRunning: { $0.isRunning })
    }
}

extension AppModel: HostableModel {}
