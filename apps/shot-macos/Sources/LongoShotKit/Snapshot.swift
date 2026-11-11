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
        let historyFolder = FileManager.default.temporaryDirectory.appendingPathComponent("LongoShot-snapshot-\(getpid())")
        let model = AppModel(live: false, defaults: UserDefaults(suiteName: suite)!, historyFolder: historyFolder)
        // A few captures in Recent, with their thumbnails made before rendering.
        let hues: [(CGFloat, CGFloat, CGFloat)] = [(1, 0.42, 0.21), (0.55, 0.36, 0.96), (0.13, 0.77, 0.37), (0.23, 0.51, 0.96),
                                                   (0.98, 0.8, 0.08), (0.94, 0.27, 0.27), (0.4, 0.4, 0.45)]
        for (red, green, blue) in hues {
            let sample = NSImage(size: CGSize(width: 320, height: 200), flipped: false) { rect in
                NSColor(red: red, green: green, blue: blue, alpha: 1).setFill()
                rect.fill()
                NSColor.white.withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 40, dy: 40), xRadius: 10, yRadius: 10).fill()
                return true
            }
            if let cg = sample.cgImage(forProposedRect: nil, context: nil, hints: nil), let png = Output.png(cg, scale: 1) {
                model.remember(file: nil, png: png)
            }
        }
        Thread.sleep(forTimeInterval: 0.5)
        let thumbnails = Task { @MainActor in for item in model.history { _ = await HistoryThumbnails.shared.load(item) }; if let first = model.history.first { _ = await HistoryThumbnails.shared.load(first, size: HistoryThumbnails.previewSize) } }
        while !thumbnails.isCancelled, HistoryThumbnails.shared.cached(model.history.last!) == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

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
                model.simulate(permission: true, recording: .captureText, system: [.captureScreen])
                model.setShortcut(Shortcut(keyCode: kVK_ANSI_A, modifiers: 0), for: .captureText)
                window(.shortcuts, model, scheme, "\(name)-3-shortcuts")
                model.simulate(permission: true)
                window(.about, model, scheme, "\(name)-4-about")
                render(MenuPopover(), model, scheme, to: directory.appendingPathComponent("\(name)-popover.png"))
                render(MenuPopover(previewing: model.history.first?.id), model, scheme,
                       to: directory.appendingPathComponent("\(name)-popover-recent.png"))
                model.simulate(permission: true, recordingScreen: 83)
                render(MenuPopover(), model, scheme, to: directory.appendingPathComponent("\(name)-popover-recording.png"))
                model.simulate(permission: true, recordingScreen: 83, paused: true)
                render(MenuPopover(), model, scheme, to: directory.appendingPathComponent("\(name)-popover-paused.png"))
                render(RecordingBar.preview, model, scheme, to: directory.appendingPathComponent("\(name)-bar-paused.png"))
                model.simulate(permission: true, recordingScreen: 83)
                render(RecordingBar.preview, model, scheme, to: directory.appendingPathComponent("\(name)-bar.png"))
                render(RecordToolbar { _ in }, model, scheme, to: directory.appendingPathComponent("\(name)-record-toolbar.png"))
                model.simulate(permission: true)
            }
        }
        // The adjustable recording frame, over a stand-in desktop: still, and while it's being moved.
        if let screen = NSScreen.main {
            let desktop = NSImage(size: screen.frame.size, flipped: false) { rect in
                NSGradient(colors: [NSColor(red: 0.98, green: 0.55, blue: 0.35, alpha: 1), NSColor(red: 0.45, green: 0.32, blue: 0.9, alpha: 1)])?
                    .draw(in: rect, angle: -35)
                NSColor(white: 0.12, alpha: 0.92).setFill()
                NSBezierPath(roundedRect: CGRect(x: rect.width * 0.18, y: rect.height * 0.3, width: rect.width * 0.4, height: rect.height * 0.42),
                             xRadius: 12, yRadius: 12).fill()
                return true
            }
            let area = CGRect(x: screen.frame.width * 0.22, y: screen.frame.height * 0.24, width: screen.frame.width * 0.46, height: screen.frame.height * 0.42)
            for (name, dragging) in [("frame", false), ("frame-dragging", true)] {
                if let image = SelectionOverlay.preview(over: desktop, area: area, dragging: dragging), let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: directory.appendingPathComponent("record-\(name).png"))
                }
            }
        }

        // The drawing window, with one mark of each kind on a stand-in capture.
        let sample = NSImage(size: CGSize(width: 1200, height: 760), flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1), NSColor(red: 0.85, green: 0.88, blue: 0.95, alpha: 1)])?
                .draw(in: rect, angle: -90)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: CGRect(x: 120, y: 160, width: 700, height: 440), xRadius: 18, yRadius: 18).fill()
            ("Meeting notes · Ship v0.2 on Friday" as NSString).draw(at: CGPoint(x: 170, y: 520),
                withAttributes: [.font: NSFont.systemFont(ofSize: 34, weight: .semibold), .foregroundColor: NSColor.black])
            return true
        }
        if let cgSample = sample.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let drawing = AnnotationState(pixelsPerPoint: 1)
            let pick = { (index: Int) in NSColor(AnnotationState.palette[index]).cgColor }
            drawing.marks = [
                Mark(tool: .highlighter, points: (0...20).map { CGPoint(x: 170 + CGFloat($0) * 30, y: 220) }, color: pick(2), width: 6),
                Mark(tool: .rectangle, points: [CGPoint(x: 150, y: 180), CGPoint(x: 820, y: 260)], color: pick(0), width: 10),
                Mark(tool: .arrow, points: [CGPoint(x: 1400, y: 900), CGPoint(x: 860, y: 300)], color: pick(0), width: 10),
                Mark(tool: .arrow, points: [CGPoint(x: 1500, y: 1250), CGPoint(x: 1900, y: 1000)], color: pick(4), width: 6),
                Mark(tool: .pen, points: (0...40).map { CGPoint(x: 900 + 120 * cos(Double($0) / 6), y: 200 + 60 * sin(Double($0) / 6)) },
                     color: pick(4), width: 5),
            ]
            render(AnnotatorView(image: cgSample, state: drawing) { _ in }.frame(width: 1100, height: 760), model, "dark",
                   to: directory.appendingPathComponent("draw-window.png"))
            for language in AppLanguage.allCases {
                model.language = language
                render(DrawToolbar(state: drawing) { _ in }, model, "dark",
                       to: directory.appendingPathComponent("draw-toolbar-\(language.rawValue).png"))
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
        try? FileManager.default.removeItem(at: historyFolder)
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
