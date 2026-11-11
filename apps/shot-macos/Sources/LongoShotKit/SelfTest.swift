import AppKit
import Carbon.HIToolbox
import ImageIO
import LongoKitUI
import Vision
import AVFoundation

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
        check("Capture Area is ⌥⇧1 by default", defaults[.captureArea] == Shortcut(keyCode: kVK_ANSI_1, modifiers: optionShift))

        // Settings, in a throwaway suite.
        let suite = "LongoShot.selftest"
        UserDefaults().removePersistentDomain(forName: suite)
        let model = AppModel(live: false, defaults: UserDefaults(suiteName: suite)!)
        check("Saves to Downloads by default", model.saveFolder.lastPathComponent == "Downloads")
        let taken = defaults[.captureArea]!
        check("A shortcut another action has is refused", !model.setShortcut(taken, for: .captureScreen) && model.shortcutError?.action == .captureScreen)
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
        let first = GlobalHotKey(keyCode: kVK_F19, modifiers: controlKey | optionKey | shiftKey | cmdKey) {}
        let second = GlobalHotKey(keyCode: kVK_F18, modifiers: controlKey | optionKey | shiftKey | cmdKey) {}
        check("Two hot keys register side by side", first.isRegistered && second.isRegistered)
        // In LongoKit every module makes hot keys in one process; a press must only reach its own.
        check("Hot keys get ids of their own", first.id != second.id)

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

        // Recording.
        check("Video sizes are even", Recorder.videoSize(CGSize(width: 1001.4, height: 667.6)) == (1000, 668))
        check("A tiny area still makes a video", Recorder.videoSize(CGSize(width: 1, height: 0)) == (2, 2))
        check("H.264 up to 4096 pixels wide", Recorder.codec(width: 3024, height: 1964) == .h264)
        check("HEVC beyond that (5K screens)", Recorder.codec(width: 5120, height: 2880) == .hevc)
        check("Recording time reads 0:07", RecordingBar.time(7) == "0:07")
        check("Recording time reads 1:02:03", RecordingBar.time(3723) == "1:02:03")
        check("Recordings are named like captures", Output.fileName(at: date, extension: "mp4") == "Longo Shot 2026-11-11 at 09.05.07.mp4")
        check("Recording settings: 30 fps, pointer and clicks shown, no sound by default",
              model.recordFramesPerSecond == 30 && model.recordCursor && model.recordClicks && !model.recordSystemAudio && !model.recordMicrophone)
        check("A countdown before recording, by default", model.recordCountdown)
        check("Defaults: ⌥⇧1 area or window, ⌥⇧2 screen, ⌥⇧3 text, ⌥⇧4 record",
              [ShotAction.captureArea, .captureScreen, .captureText, .record].enumerated().allSatisfy { index, action in
                  defaults[action] == Shortcut(keyCode: [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4][index], modifiers: optionShift)
              })
        check("Pause / Resume has no shortcut by default (it's on the recording bar)", defaults[.pauseRecording] == nil)
        // Shortcuts saved by 0.1: left as they came, they move to the new layout; changed ones are kept.
        let oldSuite = "LongoShot.selftest.old"
        UserDefaults().removePersistentDomain(forName: oldSuite)
        let old = UserDefaults(suiteName: oldSuite)!
        old.set(try? JSONEncoder().encode(ShotAction.defaults01), forKey: "shortcuts")
        check("0.1's default shortcuts move to the new layout", AppModel(live: false, defaults: old).shortcuts == defaults)
        var changed = ShotAction.defaults01
        changed["record"] = Shortcut(keyCode: kVK_ANSI_R, modifiers: cmdKey | shiftKey)
        old.set(try? JSONEncoder().encode(changed), forKey: "shortcuts")
        let kept = AppModel(live: false, defaults: old)
        check("Shortcuts changed in 0.1 are kept", kept.shortcuts[.record] == changed["record"] && kept.shortcuts[.captureText] == changed["captureText"])
        UserDefaults().removePersistentDomain(forName: oldSuite)

        // Recent captures.
        let historySuite = "LongoShot.selftest.history"
        UserDefaults().removePersistentDomain(forName: historySuite)
        let historyFolder = FileManager.default.temporaryDirectory.appendingPathComponent("LongoShot-history-\(getpid())")
        let recent = AppModel(live: false, defaults: UserDefaults(suiteName: historySuite)!, historyFolder: historyFolder)
        let small = Output.png(drawText(["1"]), scale: 1)!
        for _ in 0..<12 { recent.remember(file: nil, png: small) }
        Thread.sleep(forTimeInterval: 0.5)
        let cachedFiles = (try? FileManager.default.contentsOfDirectory(atPath: historyFolder.path)) ?? []
        check("Recent keeps the last 10", recent.history.count == 10)
        check("Clipboard-only captures are kept in the cache, and only the last 10", cachedFiles.count == 10)
        check("The newest comes first", recent.history.first.map { cachedFiles.contains($0.file.lastPathComponent) } ?? false)
        let savedFile = folder.appendingPathComponent("saved.png")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? small.write(to: savedFile)
        recent.remember(file: savedFile, png: small)
        check("A saved capture is only pointed to", recent.history.first?.file == savedFile && recent.history.first?.cached == false)
        try? FileManager.default.removeItem(at: savedFile)
        recent.pruneHistory()
        check("A file that's gone leaves the list", !recent.history.contains { $0.file == savedFile })
        let reopened = AppModel(live: false, defaults: UserDefaults(suiteName: historySuite)!, historyFolder: historyFolder)
        check("Recent is remembered", reopened.history.map(\.id) == recent.history.map(\.id))
        reopened.keepHistory = false
        Thread.sleep(forTimeInterval: 0.5)
        check("Turning History off forgets everything", reopened.history.isEmpty && !FileManager.default.fileExists(atPath: historyFolder.path))
        reopened.remember(file: nil, png: small)
        check("…and nothing new is kept", reopened.history.isEmpty)
        UserDefaults().removePersistentDomain(forName: historySuite)
        try? FileManager.default.removeItem(at: historyFolder)
        try? FileManager.default.removeItem(at: folder)

        // Sounds: all from macOS.
        // Sounds a macOS doesn't have are skipped when played, so only the shutter is required.
        let missing = Sound.allCases.filter { !$0.isAvailable }
        if !missing.isEmpty { print("      sounds this macOS doesn't have (skipped): \(missing)") }
        check("The screenshot sound is one macOS has", Sound.shutter.isAvailable)

        // Drawing on a capture.
        let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1)
        let arrow = Mark(tool: .arrow, points: [CGPoint(x: 100, y: 60), CGPoint(x: 600, y: 60)], color: red, width: 10)
        let drawn = Mark.render([arrow], on: image)
        check("A drawn capture keeps its size", drawn?.width == image.width && drawn?.height == image.height)
        if let drawn, let pixels = drawn.dataProvider?.data as Data?, let space = drawn.colorSpace, space.model == .rgb {
            // The shaft runs 60 px from the top (in image pixels): that row should now be red.
            let offset = 60 * drawn.bytesPerRow + 350 * (drawn.bitsPerPixel / 8)
            check("The arrow is drawn on the picture, from the top-left", pixels[offset] > 200 && pixels[offset + 1] < 60)
        }
        let click = Mark(tool: .arrow, points: [CGPoint(x: 5, y: 5), CGPoint(x: 7, y: 6)], color: red, width: 10)
        check("A click without a drag draws nothing", !click.isVisible && arrow.isVisible)
        let drawing = AnnotationState(pixelsPerPoint: 2)
        drawing.size = 2
        drawing.begin(at: .zero); drawing.extend(to: CGPoint(x: 200, y: 0)); drawing.end()
        check("Line widths follow the pixel density (thick = 9 pt = 18 px on Retina)", drawing.marks.first?.width == 18)
        drawing.undo()
        check("Undo takes the last mark away", drawing.marks.isEmpty && drawing.undone.count == 1)
        drawing.redo()
        check("Redo puts it back", drawing.marks.count == 1 && drawing.undone.isEmpty)

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

    /// `LongoShot --record-test <file.mp4>`: records the main screen for 3 seconds and reports the file. Needs Screen
    /// Recording, so run it through `open` to use the app's own permission.
    static var isRecordTestRequested: Bool { CommandLine.arguments.contains("--record-test") }

    @MainActor
    static func recordAndExit() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--record-test"), index + 1 < args.count else { exit(2) }
        let url = URL(fileURLWithPath: args[index + 1])
        try? FileManager.default.removeItem(at: url)
        let screen = NSScreen.main!
        Task { @MainActor in
            do {
                // Like a real recording: a countdown with the stream paused, 1 s recorded, a 2 s pause, 1 s more, with
                // the countdown, the recording bar and the menu bar timer on screen. The video should last ~2 s, not ~4.
                let recorder = try await Recorder.start(.area(display: screen.displayID, rect: .null, scale: screen.backingScaleFactor),
                                                        options: .init(systemAudio: true), to: url, paused: true)
                let model = ShotAppDelegate.model
                let area = CGRect(x: 100, y: 100, width: 400, height: 300)
                let countdown = CountdownPanel()
                countdown.show(on: screen, area: area, model: model)
                let countdownSize = countdown.size
                for count in [3, 2, 1] {
                    model.simulate(permission: true, countdown: count)
                    try await Task.sleep(nanoseconds: 330_000_000)
                }
                countdown.hide()
                recorder.resume()
                let bar = RecordingBar()
                bar.show(on: screen, area: area, model: model)
                let barSize = bar.size
                for (step, paused) in [(0, false), (1, false), (1, true), (1, true), (1, true), (1, true), (2, false), (3, false)] {
                    if paused { recorder.pause() } else { recorder.resume() }
                    model.simulate(permission: true, recordingScreen: step, paused: paused)
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
                bar.hide()
                model.simulate(permission: true)
                let saved = try await recorder.stop()
                let asset = AVURLAsset(url: saved)
                let duration = try await asset.load(.duration)
                let video = try await asset.loadTracks(withMediaType: .video).first
                let size = try await video?.load(.naturalSize) ?? .zero
                let audio = try await asset.loadTracks(withMediaType: .audio).count
                let bytes = (try? FileManager.default.attributesOfItem(atPath: saved.path)[.size] as? Int) ?? 0
                print(String(format: "recorded %.1f s, %d×%d, %d audio track(s), %d KB → %@", CMTimeGetSeconds(duration),
                             Int(size.width), Int(size.height), audio, bytes / 1024, saved.path))
                let seconds = CMTimeGetSeconds(duration)
                let ok = seconds > 1.6 && seconds < 2.9
                print(ok ? "PASS  the 2 s pause isn't in the video" : "FAIL  expected about 2 s")
                // A panel measured wrong is there but invisible, with no Stop to press.
                let shown = barSize.width > 150 && barSize.height > 30 && countdownSize.width > 100 && countdownSize.height > 100
                print("\(shown ? "PASS" : "FAIL")  the countdown (\(Int(countdownSize.width))×\(Int(countdownSize.height))) and the recording bar (\(Int(barSize.width))×\(Int(barSize.height))) are on screen")
                exit(ok && shown ? 0 : 1)
            } catch {
                print("record test failed: \(error.localizedDescription)")
                exit(1)
            }
        }
    }

    /// `LongoShot --draw-test`: opens the in-place editor on a sample picture and checks it's on screen with its
    /// toolbar under the area. Nothing is captured, so it needs no permission.
    static var isDrawTestRequested: Bool { CommandLine.arguments.contains("--draw-test") }

    @MainActor
    static func drawAndExit() {
        guard let screen = NSScreen.main else { exit(2) }
        let image = drawText(["Hello LongoKit 2026", "Xin chào Việt Nam"])
        let area = CGRect(x: 200, y: 200, width: 450, height: 125)
        InPlaceEditor.open(image, scale: 2, on: screen, area: area) { _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let frame = InPlaceEditor.frame ?? .zero
            // The area's top-left on screen, and the toolbar (~52 pt) under it.
            let top = screen.frame.maxY - frame.maxY
            let ok = InPlaceEditor.isOpen && abs(top - area.minY) < 1 && frame.height > area.height + 50 && frame.width >= area.width
            print("\(ok ? "PASS" : "FAIL")  the editor is on screen where the area was, with its toolbar under it (\(Int(frame.width))×\(Int(frame.height)))")
            InPlaceEditor.cancel()
            print(InPlaceEditor.isOpen ? "FAIL  Esc / Cancel closes it" : "PASS  Esc / Cancel closes it")
            // A whole-screen capture: the editor covers the screen, with its toolbar inside at the bottom.
            InPlaceEditor.open(image, scale: 2, on: screen, area: .null) { _ in }
            let whole = InPlaceEditor.frame ?? .zero
            let fills = abs(whole.width - screen.frame.width) < 1 && abs(whole.height - screen.frame.height) < 1
            print("\(fills ? "PASS" : "FAIL")  a whole-screen capture is drawn on full screen, toolbar inside (\(Int(whole.width))×\(Int(whole.height)))")
            InPlaceEditor.cancel()
            // A window to draw on in place: found on its screen, inside it. The first sizable window that sits on one
            // screen (thin strips and windows across two screens have no place to draw in, by design).
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let id = windows.first { info in
                guard (info[kCGWindowLayer as String] as? Int) == 0, let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                      let frame = CGRect(dictionaryRepresentation: bounds), frame.width > 200, frame.height > 200 else { return false }
                let flipped = NSScreen.screens.first.map { CGRect(x: frame.minX, y: $0.frame.maxY - frame.maxY, width: frame.width, height: frame.height) }
                return NSScreen.screens.contains { flipped.map($0.frame.contains) ?? false }
            }?[kCGWindowNumber as String] as? CGWindowID
            let placed = id.flatMap { Capturer.place(of: $0) }
            let inside = placed.map { CGRect(origin: .zero, size: $0.0.frame.size).contains($0.1) } ?? (id == nil)
            print("\(inside ? "PASS" : "FAIL")  a window is found where it is on its screen\(placed.map { " (\(Int($0.1.width))×\(Int($0.1.height)))" } ?? "")")
            exit(ok && fills && inside && !InPlaceEditor.isOpen ? 0 : 1)
        }
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
