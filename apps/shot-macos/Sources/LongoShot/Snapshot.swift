import Carbon.HIToolbox
import LongoKitUI
import SwiftUI

/// `LongoShot --snapshot <dir>` renders the window's tabs and the menu, then quits.
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
        let suite = "LongoShot.snapshot"
        UserDefaults().removePersistentDomain(forName: suite)
        let model = AppModel(live: false, defaults: UserDefaults(suiteName: suite)!)

        for (scheme, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for language in AppLanguage.allCases {
                model.language = language
                let name = "\(scheme)-\(language.rawValue)"
                model.simulate(permission: true)
                window(.general, model, scheme, "\(name)-1-general")
                model.saveToFolder = false
                window(.general, model, scheme, "\(name)-1-clipboard-only")
                render(MenuPopover(), model, scheme, to: directory.appendingPathComponent("\(name)-popover-clipboard-only.png"))
                model.saveToFolder = true
                model.simulate(permission: false)
                window(.general, model, scheme, "\(name)-2-permission")
                model.simulate(permission: true, recording: .captureText, system: [.captureWindow])
                model.setShortcut(Shortcut(keyCode: kVK_ANSI_A, modifiers: 0), for: .captureText)
                window(.shortcuts, model, scheme, "\(name)-3-shortcuts")
                model.simulate(permission: true)
                window(.about, model, scheme, "\(name)-4-about")
                render(MenuPopover(), model, scheme, to: directory.appendingPathComponent("\(name)-popover.png"))
            }
        }
        // The menu bar icon, enlarged, on both menu bar colors.
        let icon = HStack(spacing: 24) {
            ForEach([Color.white, Color(hex: 0x1E1E22)], id: \.self) { background in
                Image(nsImage: MenuBarIcon.image).resizable().interpolation(.high)
                    .frame(width: 144, height: 144).padding(16).background(background)
            }
        }
        if let image = ImageRenderer(content: icon).nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appendingPathComponent("menubar-icon.png"))
        }
        UserDefaults().removePersistentDomain(forName: suite)
        exit(0)

        @MainActor func window(_ tab: MainTab, _ model: AppModel, _ scheme: String, _ name: String) {
            model.tab = tab
            render(WindowFrame(blur: false) {
                TitleBar()
                TabBar()
                TabContent(tab: tab)
                WindowFooter()
            }, model, scheme, to: directory.appendingPathComponent("\(name).png"))
        }
    }

    @MainActor
    private static func render<V: View>(_ view: V, _ model: AppModel, _ scheme: String, to url: URL) {
        let content = view.environmentObject(model)
            .environment(\.colorScheme, scheme == "dark" ? .dark : .light)
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
