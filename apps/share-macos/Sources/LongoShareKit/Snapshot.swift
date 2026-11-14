import LongoKitUI
import SwiftUI

/// `LongoShare --snapshot <dir>` renders the window's pages, the popover and the small windows with sample devices,
/// then quits.
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
        let suite = "LongoShare.snapshot"
        UserDefaults().removePersistentDomain(forName: suite)
        let model = AppModel(live: false, defaults: UserDefaults(suiteName: suite)!)
        model.alias = "Long's MacBook"
        let mac = Peer(info: DeviceInfo(alias: "Long's PC", deviceModel: "Windows", fingerprint: "a1"), address: "192.168.1.24")
        let phone = Peer(info: DeviceInfo(alias: "Pixel 8", deviceModel: "Google", deviceType: "mobile", fingerprint: "b2"), address: "192.168.1.31")
        let pad = Peer(info: DeviceInfo(alias: "iPad", deviceModel: "iPad", deviceType: "tablet", fingerprint: "c3"), address: "192.168.1.40")
        let day = Date(timeIntervalSince1970: 1_794_640_000)
        model.simulate(peers: [mac, phone, pad], current: Transfer(device: "Pixel 8", sending: false, done: 38_400_000, total: 61_200_000),
                       notice: nil,
                       history: [HistoryItem(sent: false, device: "Pixel 8", files: ["IMG_2041.jpg", "IMG_2042.jpg", "IMG_2043.jpg"], time: day),
                                 HistoryItem(sent: true, device: "Long's PC", files: ["Báo cáo quý 3.pdf"], time: day.addingTimeInterval(-1800)),
                                 HistoryItem(sent: false, device: "iPad", text: "https://longokit.vercel.app", time: day.addingTimeInterval(-40000))],
                       trusted: [TrustedDevice(fingerprint: "a1", alias: "Long's PC")])
        let incoming = IncomingTransfer(from: phone, files: [
            ShareFile(id: "1", fileName: "IMG_2044.jpg", size: 3_480_000, fileType: "image/jpeg"),
            ShareFile(id: "2", fileName: "IMG_2045.jpg", size: 2_910_000, fileType: "image/jpeg"),
            ShareFile(id: "3", fileName: "Ghi âm 14-11.m4a", size: 812_000, fileType: "audio/mp4"),
        ])

        for (scheme, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            for language in AppLanguage.allCases {
                model.language = language
                let prefix = "\(scheme)-\(language.rawValue)"
                for (index, tab) in MainTab.allCases.enumerated() {
                    model.tab = tab
                    render(WindowFrame(blur: false) {
                        TitleBar()
                        TabBar()
                        TabContent(tab: tab)
                        WindowFooter()
                    }, model, scheme, to: directory.appendingPathComponent("\(prefix)-\(index + 1)-\(tab).png"))
                }
                render(MenuPopover(), model, scheme, to: directory.appendingPathComponent("\(prefix)-popover.png"))
                render(IncomingView(transfer: incoming) { _, _ in }.padding(20).frame(width: 440), model, scheme,
                       to: directory.appendingPathComponent("\(prefix)-incoming.png"))
                render(MessageView(from: pad, text: "Gửi bạn link nè: https://longokit.vercel.app") {}.padding(20).frame(width: 440), model, scheme,
                       to: directory.appendingPathComponent("\(prefix)-message.png"))
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
