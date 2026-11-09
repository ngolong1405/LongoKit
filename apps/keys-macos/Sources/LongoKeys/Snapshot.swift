import LongoKitUI
import SwiftUI

/// `LongoKeys --snapshot <dir>` renders the window and the popover with sample keyboards, then quits.
enum Snapshot {
    static var outputDirectory: String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static var isRequested: Bool { outputDirectory != nil }

    @MainActor
    static func renderAndExit() {
        DSSlider.scrollWheelAdjusts = false
        let directory = URL(fileURLWithPath: outputDirectory!)
        let suite = "LongoKeys.snapshot"
        UserDefaults().removePersistentDomain(forName: suite)
        let model = AppModel(live: false, defaults: UserDefaults(suiteName: suite)!)
        let builtin = KeyboardDevice(id: "builtin", name: "Built-in Keyboard", transport: "SPI", vendorID: 0x5AC, productID: 0x342,
                                     locationID: 0x33, isBuiltIn: true)
        let keychron = KeyboardDevice(id: "keychron", name: "Keychron K8", transport: "Bluetooth", vendorID: 0x5AC, productID: 0x24F,
                                      locationID: 1, isBuiltIn: false)
        model.simulate(keyboards: [builtin, keychron], shared: KeyboardProfile(caps: .hyper),
                       profiles: ["keychron": KeyboardProfile(remaps: KeyboardProfile.swapCommandOption, caps: .hyper)])

        let shots: [(String, MainTab, String?)] = [("1-general", .general, nil), ("2-keyboards", .keyboards, nil),
                                                   ("3-keyboard", .keyboards, "keychron"), ("4-hyper", .hyper, nil)]
        for (scheme, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for language in AppLanguage.allCases {
                model.language = language
                for (name, tab, key) in shots {
                    model.tab = tab
                    model.openKeyboard = key
                    render(WindowFrame(blur: false) {
                        TitleBar()
                        TabBar()
                        TabContent(tab: tab)
                        WindowFooter(tab: tab)
                    }, model, scheme, to: directory.appendingPathComponent("\(scheme)-\(language.rawValue)-\(name).png"))
                }
                render(MenuPopover(), model, scheme, to: directory.appendingPathComponent("\(scheme)-\(language.rawValue)-popover.png"))
                Pickers.flattened = true
                render(TargetPicker(key: .escape, current: .tab) { _ in } dismiss: {}, model, scheme,
                       to: directory.appendingPathComponent("\(scheme)-\(language.rawValue)-remap-picker.png"))
                render(HyperActionPicker(key: .letter("j"), current: .key(.down)) { _ in } dismiss: {}, model, scheme,
                       to: directory.appendingPathComponent("\(scheme)-\(language.rawValue)-hyper-picker.png"))
                Pickers.flattened = false
            }
        }
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
