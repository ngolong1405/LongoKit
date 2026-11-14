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
        func at(_ minutes: Double) -> Date { day.addingTimeInterval(minutes * 60) }
        let chat = Conversation(id: "b2", alias: "Pixel 8", deviceModel: "Google", deviceType: "mobile", items: [
            ChatItem(sent: false, text: "Gửi mình mấy tấm hình hôm qua nha", state: .done, time: at(0)),
            ChatItem(sent: true, files: [ChatFile(name: "IMG_2041.jpg", size: 3_480_000), ChatFile(name: "IMG_2042.jpg", size: 2_910_000)],
                     state: .done, time: at(2), done: 6_390_000, total: 6_390_000),
            ChatItem(sent: true, text: "Xong rồi đó. Link bài viết: https://longokit.vercel.app/share", state: .done, time: at(3)),
            ChatItem(sent: false, files: [ChatFile(name: "Ghi âm 14-11.m4a", size: 812_000), ChatFile(name: "Báo cáo quý 3.pdf", size: 1_240_000)],
                     state: .asking, time: at(5), total: 2_052_000),
            ChatItem(sent: true, files: [ChatFile(name: "video-4k.mov", size: 61_200_000)], state: .transferring, time: at(6),
                     done: 38_400_000, total: 61_200_000),
        ], unread: 0)
        let older = Conversation(id: "c3", alias: "iPad", deviceModel: "iPad", deviceType: "tablet", items: [
            ChatItem(sent: false, text: "https://longokit.vercel.app", state: .done, time: at(-900)),
        ], unread: 2)
        let away = Conversation(id: "d4", alias: "Logan's MacBook Air", deviceModel: "macOS", deviceType: "desktop", items: [
            ChatItem(sent: false, text: "tôi sẽ xem", state: .done, time: at(-3000)),
        ])
        model.simulate(peers: [mac, phone, pad], conversations: [chat, older, away], selected: "b2",
                       trusted: [TrustedDevice(fingerprint: "a1", alias: "Long's PC")])

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
