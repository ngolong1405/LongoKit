import LongoKitUI
import SwiftUI

/// `LongoKit --snapshot <dir>` renders the window's pages and the menu, then quits.
enum Snapshot {
    static var outputDirectory: String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static var isRequested: Bool { outputDirectory != nil }

    @MainActor
    static func renderAndExit() {
        let directory = URL(fileURLWithPath: outputDirectory!)
        let suiteName = "LongoKit.snapshot"
        let storePrefix = "LongoKit.snapshot."
        func clean() {
            UserDefaults().removePersistentDomain(forName: suiteName)
            for info in ModuleInfo.all { UserDefaults().removePersistentDomain(forName: storePrefix + info.id) }
        }
        clean()
        let defaults = UserDefaults(suiteName: suiteName)!
        // Three on, Keys waiting for its own app to quit.
        defaults.set(["mouse", "display", "shot", "keys", "share"], forKey: "modules")
        let suite = Suite(live: false, defaults: defaults, storeName: { storePrefix + $0 }, runsElsewhere: { $0.id == "keys" })
        suite.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        for (scheme, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for language in AppLanguage.allCases {
                suite.language = language
                let name = "\(scheme)-\(language.rawValue)"
                let pages: [(String, Suite.Page)] = [("1-general", .general), ("2-mouse", .module("mouse")), ("3-display", .module("display")),
                                                    ("4-keys-elsewhere", .module("keys")), ("5-shot", .module("shot")), ("6-share", .module("share")),
                                                    ("7-about", .about)]
                for (file, page) in pages {
                    suite.page = page
                    render(KitWindow(forSnapshot: true), suite, scheme, to: directory.appendingPathComponent("\(name)-\(file).png"))
                }
                for id in ["mouse", "display", "shot", "share"] {
                    suite.menuModule = id
                    render(KitMenu(), suite, scheme, to: directory.appendingPathComponent("\(name)-menu-\(id).png"))
                }
            }
        }
        // A module that's off, and the menu with nothing on.
        suite.language = .english
        suite.setEnabled(ModuleInfo.named("display")!, false)
        suite.page = .module("display")
        NSApp.appearance = NSAppearance(named: .darkAqua)
        render(KitWindow(forSnapshot: true), suite, "dark", to: directory.appendingPathComponent("dark-en-8-display-off.png"))
        for id in ["mouse", "shot", "share"] { suite.setEnabled(ModuleInfo.named(id)!, false) }
        render(KitMenu(), suite, "dark", to: directory.appendingPathComponent("dark-en-menu-all-off.png"))
        clean()
        exit(0)
    }

    @MainActor
    private static func render<V: View>(_ view: V, _ suite: Suite, _ scheme: String, to url: URL) {
        let content = view.environmentObject(suite)
            .environment(\.colorScheme, scheme == "dark" ? .dark : .light)
            .environment(\.rendersFlat, true)
            .padding(40)
            .background(scheme == "dark" ? Color(hex: 0x0E1015) : Color(hex: 0xD9DCE3))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }
}
