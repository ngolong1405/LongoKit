import LongoKitUI
import Network
import SwiftUI

/// `LongoFlow --snapshot <dir>` renders the window's pages and the popover with sample Macs, then quits.
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
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "LongoFlow.snapshot"
        UserDefaults().removePersistentDomain(forName: suite)
        let model = AppModel(live: false, defaults: UserDefaults(suiteName: suite)!)
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 1)
        let air = PairedMac(id: "air", name: "Logan's MacBook Air", key: Data(), side: .right)
        let studio = PairedMac(id: "studio", name: "Mac Studio", key: Data(), side: .left)
        let states: [(String, Pairing)] = [("1-macs", .none), ("1-showing", .showing("Logan's MacBook Air", code: "482915")),
                                           ("1-typing", .typing("Mac mini", wrong: false))]
        for (scheme, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for language in AppLanguage.allCases {
                model.language = language
                let prefix = "\(scheme)-\(language.rawValue)"
                for (name, pairing) in states {
                    model.simulate(nearby: [NearbyMac(id: "mini", name: "Mac mini", endpoint: endpoint)], paired: [air, studio],
                                   connected: ["air"], pairing: pairing, access: name != "1-macs")
                    model.tab = .devices
                    render(window(.devices), model, scheme, to: directory.appendingPathComponent("\(prefix)-\(name).png"))
                }
                for (index, tab) in [MainTab.general, .about].enumerated() {
                    model.tab = tab
                    render(window(tab), model, scheme, to: directory.appendingPathComponent("\(prefix)-\(index + 2)-\(tab).png"))
                }
                render(MenuPopover(), model, scheme, to: directory.appendingPathComponent("\(prefix)-popover.png"))
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
    private static func window(_ tab: MainTab) -> some View {
        WindowFrame(blur: false) {
            TitleBar()
            TabBar()
            TabContent(tab: tab)
            WindowFooter()
        }
    }

    @MainActor
    private static func render<V: View>(_ view: V, _ model: AppModel, _ scheme: String, to url: URL) {
        let content = view.environmentObject(model)
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
