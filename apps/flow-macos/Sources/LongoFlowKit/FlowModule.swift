import LongoKitUI
import SwiftUI

/// Longo Flow as a module: what a host needs to run it.
public enum FlowModule: LongoModule {
    public static let id = "flow"
    public static let title = "Flow"
    public static let bundleIdentifier = "com.longokit.flow"
    public static var vietnamese: [String: String] { Vietnamese.strings }
    public static var resourceFolder = ""

    @MainActor public static func host(defaults: UserDefaults, live: Bool) -> any HostedModule {
        let model = AppModel(live: live, defaults: defaults)
        // About is the host's own page.
        if model.tab == .about { model.tab = .devices }
        return ModelHost(model: model, panel: { ModulePanel() }, menu: { MenuPopover() },
                         isOn: { $0.isEnabled },
                         isRunning: { $0.isEnabled && $0.hasAccessibility },
                         setRunning: { $0.isEnabled = $1 },
                         prepareToQuit: { model, done in
                             model.prepareToQuit()
                             done()
                         })
    }
}
