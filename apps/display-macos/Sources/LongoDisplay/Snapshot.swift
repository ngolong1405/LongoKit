import LongoKitUI
import SwiftUI

/// `LongoDisplay --snapshot <dir>` renders the window and the popover with sample displays, then quits.
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
        let suite = "LongoDisplay.snapshot"
        UserDefaults().removePersistentDomain(forName: suite)
        let model = AppModel(live: false, defaults: UserDefaults(suiteName: suite)!)
        let builtin = Display(id: 1, key: "builtin", name: "Built-in", isBuiltin: true, method: .native,
                              pixelSize: CGSize(width: 3024, height: 1964))
        let dell = Display(id: 2, key: "dell", name: "DELL U2723QE", isBuiltin: false, method: .ddc,
                           pixelSize: CGSize(width: 3840, height: 2160))
        let tv = Display(id: 3, key: "tv", name: "LG TV", isBuiltin: false, method: .software,
                         pixelSize: CGSize(width: 1920, height: 1080))
        var dellSettings = DisplaySettings()
        dellSettings.brightness = 0.62
        dellSettings.minimum = 0.2
        dellSettings.maximum = 0.9
        model.simulate(displays: [builtin, dell, tv], settings: ["builtin": DisplaySettings(), "dell": dellSettings, "tv": DisplaySettings()],
                       powerOff: ["tv": .disabled])

        let shots: [(String, MainTab, String?)] = [("1-general", .general, nil), ("2-displays", .displays, nil), ("3-display", .displays, "dell")]
        for (scheme, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for language in AppLanguage.allCases {
                model.language = language
                for (name, tab, key) in shots {
                    model.tab = tab
                    model.openDisplayKey = key
                    render(WindowFrame(blur: false) {
                        TitleBar()
                        TabBar()
                        TabContent(tab: tab)
                        WindowFooter(tab: tab)
                    }, model, scheme, to: directory.appendingPathComponent("\(scheme)-\(language.rawValue)-\(name).png"))
                }
                render(MenuPopover(), model, scheme, to: directory.appendingPathComponent("\(scheme)-\(language.rawValue)-popover.png"))
            }
        }
        // The menu bar icon, enlarged, on both menu bar colors.
        let icon = HStack(spacing: 24) {
            ForEach([Color.white, Color(hex: 0x1E1E22)], id: \.self) { background in
                Image(nsImage: MenuBarIcon.image).renderingMode(.template).resizable().interpolation(.high)
                    .foregroundStyle(background == .white ? Color.black : Color.white)
                    .frame(width: 144, height: 144).padding(16).background(background)
            }
        }
        if let image = ImageRenderer(content: icon).nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appendingPathComponent("menubar-icon.png"))
        }
        UserDefaults().removePersistentDomain(forName: suite)
        exit(0)
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
