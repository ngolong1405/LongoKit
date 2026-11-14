import AppKit
import LongoDisplayKit
import LongoKeysKit
import LongoKitUI
import LongoMouseKit
import LongoShareKit
import LongoFlowKit
import LongoShotKit

/// One of the modules LongoKit holds, and what the app shows about it.
struct ModuleInfo: Identifiable {
    let type: any LongoModule.Type
    /// What it does, in a few words (English, shown through `L`).
    let blurb: String

    var id: String { type.id }
    var title: String { type.title }
    /// Its stand-alone app's name, like "Longo Mouse".
    var appName: String { "Longo " + type.title }

    func logo(dark: Bool) -> NSImage? {
        (dark ? nil : type.image("LogoLight.png")) ?? type.image("Logo.png")
    }

    /// In sidebar order.
    static let all: [ModuleInfo] = [
        ModuleInfo(type: MouseModule.self, blurb: "Buttons, gestures & smooth scrolling"),
        ModuleInfo(type: DisplayModule.self, blurb: "Brightness & volume for every display"),
        ModuleInfo(type: KeysModule.self, blurb: "Key remapping & the Hyper layer"),
        ModuleInfo(type: ShotModule.self, blurb: "Screenshots, recording & copying text on screen"),
        ModuleInfo(type: ShareModule.self, blurb: "Files between your devices, nearby"),
        ModuleInfo(type: FlowModule.self, blurb: "One keyboard and mouse for your Macs"),
    ]

    static func named(_ id: String) -> ModuleInfo? {
        all.first { $0.id == id }
    }

    /// Once at launch: each module's images sit in a folder named after it (see scripts/build-app.sh), and its
    /// translations and the fonts get registered.
    static func prepareAll() {
        for info in all { prepare(info.type, folder: info.title + "/") }
    }

    private static func prepare<Module: LongoModule>(_ module: Module.Type, folder: String) {
        Module.resourceFolder = folder
        Module.prepare()
    }
}
