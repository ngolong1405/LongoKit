import LongoKitUI
import SwiftUI

/// `LongoMouse --snapshot <dir>` renders each tab to PNG and quits, for comparing against the Figma frames.
/// It uses a throwaway defaults suite and never starts the event tap.
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
        let suite = "MouseMapper.snapshot"
        UserDefaults().removePersistentDomain(forName: suite)
        let model = AppModel(startsEngine: false, defaults: UserDefaults(suiteName: suite)!)
        let b4 = Trigger(button: 3, modifiers: [])
        let b5 = Trigger(button: 4, modifiers: [])
        model.bindings = [
            MouseBinding(trigger: b4, clickType: .click, action: .launchpad),
            MouseBinding(trigger: b4, clickType: .scroll, action: .scrollZoom),
            MouseBinding(trigger: b4, clickType: .drag, action: .dragSpaces),
            MouseBinding(trigger: b5, clickType: .click, action: .missionControl),
            MouseBinding(trigger: b5, clickType: .scroll, action: .scrollZoom),
            MouseBinding(trigger: b5, clickType: .drag, action: .dragScroll),
        ]

        let desk = MouseDevice(id: "1133:45108:AA", product: "MX Master 3S", manufacturer: "Logitech",
                               transport: "Bluetooth Low Energy", vendorID: 0x046D, productID: 0xB034, battery: 88)
        let gaming = MouseDevice(id: "5426:154:BB", product: "DeathAdder V3 Pro", manufacturer: "Razer",
                                 transport: "USB", vendorID: 0x1532, productID: 0x009A, battery: nil)
        model.simulate(devices: [desk, gaming], active: desk.id)
        model.profiles[desk.id]?.customName = "Bàn làm việc"
        model.setIndependent(desk.id, true)
        model.profiles["1133:45082:CC"] = DeviceProfile(product: "Pebble M350", manufacturer: "Logitech", connection: "Bluetooth",
                                                         hardwareID: "046D:B01A", customName: "Pebble Di Động",
                                                         lastSeen: Date().addingTimeInterval(-86_400))
        model.editingDeviceID = desk.id

        // (name, tab, granted, open mouse page on this section)
        let shots: [(name: String, tab: MainTab, granted: Bool, section: DeviceSection?)] = [
            ("0-devices", .devices, true, nil),
            ("1-general", .general, true, nil),
            ("2-buttons", .devices, true, .buttons),
            ("2b-buttons-listening", .devices, true, .buttons),
            ("3-scrolling", .devices, true, .scrolling),
            ("4-permission", .general, false, nil),
            ("6-about", .about, true, nil),
        ]
        NSApp.appearance = NSAppearance(named: .darkAqua)
        for language in AppLanguage.allCases {
        model.language = language
        for shot in shots {
            model.simulate(granted: shot.granted)
            model.setCapturing(shot.name.hasSuffix("listening"))
            model.showingDeviceDetail = shot.section != nil
            if let section = shot.section { model.deviceSection = section }
            let view = SnapshotWindow(tab: shot.tab)
                .environmentObject(model)
                .environment(\.colorScheme, .dark)
                .padding(40)
                .background(Color(hex: 0x0E1015))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: directory.appendingPathComponent("\(language.rawValue)-\(shot.name).png"))
        }
        }
        model.language = .english
        // Light theme pass of the main tabs.
        NSApp.appearance = NSAppearance(named: .aqua)
        let lightShots: [(String, MainTab, DeviceSection?)] = [
            ("General", .general, nil), ("Devices", .devices, nil), ("Buttons", .devices, .buttons),
            ("Scrolling", .devices, .scrolling), ("About", .about, nil),
        ]
        for (name, tab, section) in lightShots {
            model.simulate(granted: true)
            model.showingDeviceDetail = section != nil
            if let section { model.deviceSection = section }
            let view = SnapshotWindow(tab: tab)
                .environmentObject(model)
                .environment(\.colorScheme, .light)
                .padding(40)
                .background(Color(hex: 0xD9DCE3))
            if let image = ImageRenderer(content: view).nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: directory.appendingPathComponent("light-\(name).png"))
            }
        }
        NSApp.appearance = NSAppearance(named: .darkAqua)

        model.simulate(granted: true)
        model.setCapturing(false)
        ActionPicker.flattened = true
        if let first = model.editing.first {
            let picker = ActionPicker(target: .init(bindingID: first.id, trigger: first.trigger, clickType: first.clickType)) {}.environmentObject(model).padding(40).background(Color(hex: 0x0E1015))
            if let image = ImageRenderer(content: picker).nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: directory.appendingPathComponent("8-action-picker.png"))
            }
        }
        let popover = MenuPopover().environmentObject(model).environment(\.colorScheme, .dark).padding(40).background(Color(hex: 0x0E1015))
        let renderer = ImageRenderer(content: popover)
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appendingPathComponent("7-menu-popover.png"))
        }
        UserDefaults().removePersistentDomain(forName: suite)
        exit(0)
    }
}

/// The main window without scroll views or AppKit glue, which ImageRenderer can't draw.
private struct SnapshotWindow: View {
    let tab: MainTab

    var body: some View {
        WindowFrame(blur: false) {
            TitleBar()
            TabBar(selection: .constant(tab))
            TabContent(tab: tab)
            WindowFooter(tab: tab)
        }
    }
}
