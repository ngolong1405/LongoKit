import AppKit
import Carbon.HIToolbox
import ImageIO
import LongoKitUI
import Vision

/// `LongoShot --selftest` checks what doesn't need the screen: shortcuts, settings, file names, PNG output and text
/// recognition on a picture it draws itself. Nothing is captured.
enum SelfTest {
    static var isRequested: Bool { CommandLine.arguments.contains("--selftest") }
    private static var failures = 0

    @MainActor
    static func runAndExit() {
        // Shortcuts.
        let optionShift = optionKey | shiftKey
        check("⌥⇧ come in menu order", Shortcut.symbols(optionShift | controlKey | cmdKey) == "⌃⌥⇧⌘")
        check("A plain letter isn't allowed", !Shortcut(keyCode: kVK_ANSI_A, modifiers: 0).isAllowed)
        check("An F-key works on its own", Shortcut(keyCode: kVK_F5, modifiers: 0).isAllowed)
        check("F5 is named F5", Shortcut.keyName(kVK_F5) == "F5")
        check("Space is named Space", Shortcut.keyName(kVK_Space) == "Space")
        check("Modifiers outside ⌘⌥⌃⇧ are dropped", Shortcut(keyCode: kVK_ANSI_1, modifiers: optionShift | alphaLock).modifiers == optionShift)
        let defaults = ShotAction.defaultShortcuts
        check("Default shortcuts are all different", Set(defaults.values).count == defaults.count)
        check("Default shortcuts are allowed", defaults.values.allSatisfy(\.isAllowed))
        check("Hot key ids are all different", Set(ShotAction.allCases.map(\.hotKeyID)).count == ShotAction.allCases.count)
        check("Capture Area is ⌥⇧1 by default", defaults[.captureArea] == Shortcut(keyCode: kVK_ANSI_1, modifiers: optionShift))

        // Settings, in a throwaway suite.
        let suite = "LongoShot.selftest"
        UserDefaults().removePersistentDomain(forName: suite)
        let model = AppModel(live: false, defaults: UserDefaults(suiteName: suite)!)
        check("Saves to Downloads by default", model.saveFolder.lastPathComponent == "Downloads")
        let taken = defaults[.captureArea]!
        check("A shortcut another action has is refused", !model.setShortcut(taken, for: .captureWindow) && model.shortcutError?.action == .captureWindow)
        check("A plain letter is refused", !model.setShortcut(Shortcut(keyCode: kVK_ANSI_K, modifiers: 0), for: .copyLast))
        let custom = Shortcut(keyCode: kVK_ANSI_K, modifiers: cmdKey | shiftKey)
        check("A free shortcut is taken", model.setShortcut(custom, for: .copyLast) && model.shortcutError == nil)
        model.clearShortcut(.captureScreen)
        model.saveToFolder = false
        model.copyToClipboard = false
        check("Turning off both saving and copying keeps saving on", model.saveToFolder && !model.copyToClipboard)
        let reloaded = AppModel(live: false, defaults: UserDefaults(suiteName: suite)!)
        check("Shortcuts are remembered", reloaded.shortcuts[.copyLast] == custom)
        check("A removed shortcut stays removed", reloaded.shortcuts[.captureScreen] == nil)
        check("Clipboard choice is remembered", !reloaded.copyToClipboard)
        reloaded.restoreDefaults()
        check("Restore defaults brings the shortcuts back", reloaded.shortcuts == ShotAction.defaultShortcuts && reloaded.copyToClipboard)
        UserDefaults().removePersistentDomain(forName: suite)

        // Hot keys: two at once each register (an unusual combination, released right away).
        let first = GlobalHotKey(keyCode: kVK_F19, modifiers: controlKey | optionKey | shiftKey | cmdKey, id: 901) {}
        let second = GlobalHotKey(keyCode: kVK_F18, modifiers: controlKey | optionKey | shiftKey | cmdKey, id: 902) {}
        check("Two hot keys register side by side", first.isRegistered && second.isRegistered)

        // Files.
        var parts = DateComponents()
        (parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second) = (2026, 11, 11, 9, 5, 7)
        let date = Calendar.current.date(from: parts)!
        check("File name has the date and time", Output.fileName(at: date) == "Longo Shot 2026-11-11 at 09.05.07.png")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LongoShot-selftest-\(getpid())")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = drawText(["Hello LongoKit 2026", "Xin chào Việt Nam"])
        let png = Output.png(image, scale: 2)
        check("PNG is written", png != nil)
        if let png {
            let saved = try? Output.save(png, in: folder, at: date)
            let again = try? Output.save(png, in: folder, at: date)
            check("Saved in the folder", saved?.lastPathComponent == "Longo Shot 2026-11-11 at 09.05.07.png")
            check("Two captures in the same second both keep their file", again?.lastPathComponent == "Longo Shot 2026-11-11 at 09.05.07 2.png")
            let properties = CGImageSourceCreateWithData(png as CFData, nil)
                .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) } as? [CFString: Any]
            check("A Retina capture is marked 144 dpi, so it opens at its on-screen size",
                  (properties?[kCGImagePropertyDPIWidth] as? Double) == 144)
        }
        try? FileManager.default.removeItem(at: folder)
        let thumbnail = PreviewPanel.thumbnail(image, maxPixels: 200)
        check("The preview keeps only a small copy", thumbnail.size.width <= 100)

        // Text recognition, on this Mac.
        let probe = VNRecognizeTextRequest()
        probe.recognitionLevel = .accurate
        let languages = (try? probe.supportedRecognitionLanguages()) ?? []
        print("      OCR languages: \(languages.joined(separator: ", "))")
        check("Vietnamese text recognition is available", languages.contains("vi-VT"))
        let done = DispatchSemaphore(value: 0)
        var english: [String] = [], vietnamese: [String] = []
        Task.detached {
            english = (try? await TextRecognizer.lines(in: image, vietnameseFirst: false)) ?? []
            vietnamese = (try? await TextRecognizer.lines(in: image, vietnameseFirst: true)) ?? []
            done.signal()
        }
        while done.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        print("      read: \(english) / \(vietnamese)")
        check("Reads English text", english.joined(separator: " ").contains("LongoKit"))
        check("Reads Vietnamese text with its marks", vietnamese.joined(separator: " ").contains("Việt Nam"))

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    /// Black text on white, the way a capture of a document would look.
    private static func drawText(_ lines: [String]) -> CGImage {
        let size = CGSize(width: 900, height: 80 + 70 * CGFloat(lines.count))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 44), .foregroundColor: NSColor.black]
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(at: NSPoint(x: 40, y: size.height - 90 - CGFloat(index) * 70), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    private static func check(_ name: String, _ ok: Bool) {
        if !ok { failures += 1 }
        print("\(ok ? "PASS" : "FAIL")  \(name)")
    }
}
