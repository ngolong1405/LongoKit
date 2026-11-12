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

        // The app's own windows, with a menu bar icon among them (its window's number isn't a window id).
        let icon = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        icon.button?.title = "S"
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let own = Capturer.ownWindows
        check("The app's windows are listed with a menu bar icon open", own.allSatisfy { $0 > 0 })
        NSStatusBar.system.removeStatusItem(icon)

        // The right-click menu of the menu bar icon: Settings, the app's switch, About, Quit.
        var toggled = false
        let menu = StatusItemMenu.standard(name: "Longo Shot", icon: nil, isOn: true, toggle: { toggled = true },
                                           settings: {}, about: {})
        check("The right-click menu has Settings, the switch, About and Quit",
              menu.items.map(\.title) == ["Settings…", "", "Longo Shot", "", "About", "Quit"])
        check("…with the switch ticked while it runs", menu.items[2].state == .on)
        _ = (menu.items[2].target as AnyObject?)?.perform(menu.items[2].action)
        check("…and clicking it switches", toggled)

        // The area while drawing: eight grips resize it, the edges move it, always on screen.
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let box = CGRect(x: 100, y: 100, width: 300, height: 200)
        check("A corner grip resizes both ways", Grip.bottomRight.resize(box, by: CGSize(width: 50, height: 20), in: bounds)
              == CGRect(x: 100, y: 100, width: 350, height: 220))
        check("A side grip resizes one way", Grip.left.resize(box, by: CGSize(width: -40, height: 99), in: bounds)
              == CGRect(x: 60, y: 100, width: 340, height: 200))
        check("Dragging past the other side flips it", Grip.right.resize(box, by: CGSize(width: -400, height: 0), in: bounds)
              == CGRect(x: 0, y: 100, width: 100, height: 200))
        check("The area moves by its edges and stays on screen", moved(box, by: CGSize(width: 900, height: -500), in: bounds)
              == CGRect(x: 700, y: 0, width: 300, height: 200))

        // The quick captures iShot uses (CoreGraphics', looked up at run time) are there, at the screen's density.
        if let screen = NSScreen.main {
            let quick = Capturer.instant(display: screen.displayID, pointWidth: screen.frame.width)
            check("Quick screen captures are available (\(quick.map { "\($0.image.width)×\($0.image.height)" } ?? "no"))",
                  quick.map { abs($0.scale - screen.backingScaleFactor) < 0.01 } ?? false)
        }

        // Captures keep the screen's own colors (Display P3 on a Mac's), so the frozen screen matches the live one.
        let colors = Capturer.colorSpace(of: CGMainDisplayID())
        check("Captures use the screen's colors (\(colors))", colors == CGColorSpace.displayP3 || colors == CGColorSpace.sRGB)

        // Drawing on a capture: cut the area first, then draw only on it; the result looks the same as drawing on the
        // whole screen and cutting after.
        let screenShot = drawText(["Meeting notes", "Ship v0.2 on Friday", "Phở at 12:30"])
        let marked = [Mark(tool: .rectangle, points: [CGPoint(x: 60, y: 40), CGPoint(x: 420, y: 150)], color: CGColor(red: 1, green: 0, blue: 0, alpha: 1), width: 8),
                      Mark(tool: .arrow, points: [CGPoint(x: 500, y: 200), CGPoint(x: 150, y: 90)], color: CGColor(red: 0, green: 0, blue: 1, alpha: 1), width: 6)]
        let partArea = CGRect(x: 25, y: 15, width: 200, height: 90)
        let before = Mark.render(marked, on: screenShot).flatMap { Capturer.cut($0, scale: 2, to: partArea) }
        let after = Capturer.cut(screenShot, scale: 2, to: partArea).flatMap { Mark.render(marked, on: $0, origin: CGPoint(x: 50, y: 30)) }
        check("Drawing on just the area matches drawing on the whole screen", samePixels(before, after))

        // On the clipboard at once: the PNG is made when it's pasted.
        let board = NSPasteboard(name: NSPasteboard.Name("LongoShot.selftest"))
        Output.promise(screenShot, scale: 2, on: board)
        let pasted = board.data(forType: .png).flatMap { NSBitmapImageRep(data: $0) }
        check("A capture is on the clipboard at once, as a PNG when pasted", pasted?.pixelsWide == screenShot.width)
        board.releaseGlobally()

        // An area cut from a frozen screen: points to pixels, from the top-left.
        let still = drawText(["Frozen"])
        let cut = Capturer.cut(still, scale: 2, to: CGRect(x: 10, y: 5, width: 100, height: 20))
        check("An area is cut from the frozen screen at its pixel size", cut?.width == 200 && cut?.height == 40)
        check("The whole frozen screen is the whole picture", Capturer.cut(still, scale: 2, to: .null)?.width == still.width)

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
        // Other scripts, each read as itself; a Latin line keeps its Vietnamese marks next to them.
        let scripts = drawText(["你好世界", "안녕하세요", "こんにちは", "สวัสดีชาวโลก", "Phở ở Hàng Bè"])
        let readAll = DispatchSemaphore(value: 0)
        var others: [String] = []
        Task.detached {
            others = (try? await TextRecognizer.lines(in: scripts, vietnameseFirst: true)) ?? []
            readAll.signal()
        }
        while readAll.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        print("      read: \(others)")
        let all = others.joined(separator: " ")
        check("Reads Chinese, Korean, Japanese and Thai", ["你好世界", "안녕하세요", "こんにちは", "สวัสดี"].allSatisfy(all.contains))
        check("…and Vietnamese marks among them", all.contains("Phở ở Hàng Bè"))
        // The text window: read as any script, or as one language; lines joined; the choice remembered.
        var remembered = ""
        let window = TextReading(scripts, language: "auto", vietnameseFirst: true) { remembered = $0 }
        func settle(_ reading: TextReading) {
            let deadline = Date().addingTimeInterval(20)
            while reading.isReading && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        settle(window)
        check("The text window reads any script at first", window.text.contains("你好世界") && window.text.contains("Phở ở Hàng Bè"))
        window.joinsLines = true
        check("…joins its lines into one paragraph", !window.text.contains("\n") && window.text.contains("你好世界 "))
        window.language = "ko-KR"
        settle(window)
        check("…reads it again as the language picked, and remembers it", remembered == "ko-KR" && window.text.contains("안녕하세요"))
        let choices = TextReading.choices.map(\.code)
        // Which languages Vision reads depends on the macOS version (older ones have fewer, without Vietnamese).
        check("…offers Automatic first, then every language Vision reads", choices.first == "auto"
              && Set(choices.dropFirst()) == Set(TextRecognizer.languages) && choices.count == TextRecognizer.languages.count + 1)

        check("Tells Latin text from other scripts", TextRecognizer.isLatin("Phở ở Hàng Bè — 12.5%") && !TextRecognizer.isLatin("Xin chào 안녕"))

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

    /// `LongoShot --text-demo`: the text window on a sample picture for a few seconds, to look at.
    static var isTextDemoRequested: Bool { CommandLine.arguments.contains("--text-demo") }

    @MainActor
    static func textDemoAndExit() {
        let sample = drawText(["Meeting notes · Ghi chú cuộc họp", "Ship v0.2 on Friday", "你好世界 · 안녕하세요", "Phở ở Hàng Bè rất ngon"])
        TextWindow.open(TextReading(sample, language: "auto", vietnameseFirst: true), scale: 1, on: NSScreen.main) { _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { exit(0) }
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
            // From the shortcut to the overlay on screen: the screens frozen (quick captures), then the overlay on them.
            for _ in 0..<3 {
                let pressed = Date()
                let still = Capturer.freezeNow() ?? [:]
                SelectionOverlay.pick(.area, hint: "", frozen: still) { _ in }
                print(String(format: "      shortcut → overlay up: %.0f ms (screens frozen: %d)", Date().timeIntervalSince(pressed) * 1000, still.count))
                SelectionOverlay.cancel()
                SelectionOverlay.dismissLingering()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            }
            // Dragging an area out: the edge follows the pointer as a layer, and the screen isn't drawn again.
            SelectionOverlay.pick(.area, hint: "") { _ in }
            var tracks = false
            if let panel = NSApp.windows.first(where: { $0.identifier == Capturer.panelID && $0.isVisible && $0.screen == screen }),
               let view = panel.contentView?.subviews.first(where: { $0.className.contains("OverlayView") }) {
                panel.displayIfNeeded()
                let height = view.bounds.height
                func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
                    NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: height - y), modifierFlags: [], timestamp: 0,
                                       windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                }
                view.mouseDown(with: mouse(.leftMouseDown, 100, 100))
                view.mouseDragged(with: mouse(.leftMouseDragged, 250, 200))
                panel.displayIfNeeded()
                let started = Date()
                for step in 1...60 { view.mouseDragged(with: mouse(.leftMouseDragged, 300 + CGFloat(step), 250)) }
                let perStep = Date().timeIntervalSince(started) * 1000 / 60
                view.mouseDragged(with: mouse(.leftMouseDragged, 400, 300))
                let edge = view.layer?.sublayers?.first { !$0.isHidden && $0.borderWidth == 1.5 }
                let expected = CGRect(x: 98.5, y: 98.5, width: 303, height: 203)
                tracks = !view.needsDisplay && edge.map { abs($0.frame.minX - expected.minX) < 0.5 && abs($0.frame.width - expected.width) < 0.5
                    && abs($0.frame.minY - expected.minY) < 0.5 && abs($0.frame.height - expected.height) < 0.5 } == true
                print(String(format: "      a drag step while picking takes %.2f ms", perStep))
            }
            SelectionOverlay.cancel()
            SelectionOverlay.dismissLingering()
            print("\(tracks ? "PASS" : "FAIL")  dragging an area out moves its edge with the pointer, without drawing the screen again")
            // The selection overlay stays a moment after a pick (until the editor takes over); the pointer moving over
            // it meanwhile is harmless.
            SelectionOverlay.pick(.area, hint: "") { _ in }
            let overlayViews = NSApp.windows.filter { $0.identifier == Capturer.panelID && $0.isVisible }
                .compactMap { $0.contentView.map { [$0] + $0.subviews } }.flatMap { $0 }
            SelectionOverlay.cancel()
            let moved = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
            for view in overlayViews { view.mouseMoved(with: moved) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            for view in overlayViews { view.mouseMoved(with: moved) }
            let quiet = !overlayViews.isEmpty && overlayViews.allSatisfy { $0.trackingAreas.isEmpty || !($0.className.contains("OverlayView")) }
            print("\(quiet ? "PASS" : "FAIL")  the selection overlay stops following the pointer once done, and can't crash before it's gone")
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            // The whole screen at hand: the editor covers it and the area stays adjustable.
            let size = screen.frame.size
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let canvas = CGContext(data: nil, width: Int(size.width * 2), height: Int(size.height * 2), bitsPerComponent: 8,
                                   bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            // A pattern, so where the area's part sits can be seen (stripes every 100 pt).
            for stripe in 0..<Int(size.width / 50) {
                canvas.setFillColor(stripe % 2 == 0 ? CGColor(red: 1, green: 0.42, blue: 0.21, alpha: 1) : CGColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1))
                canvas.fill(CGRect(x: stripe * 100, y: 0, width: 100, height: Int(size.height * 2)))
            }
            let still = canvas.makeImage()!
            let opening = Date()
            InPlaceEditor.open(screen: still, scale: 2, on: screen, area: area) { _ in }
            print(String(format: "      the editor opened in %.0f ms", Date().timeIntervalSince(opening) * 1000))
            let adjustable = InPlaceEditor.area == area && abs((InPlaceEditor.frame ?? .zero).width - size.width) < 1
            print("\(adjustable ? "PASS" : "FAIL")  an area to draw on keeps the whole screen, so it can still be resized")
            let arrows = Grip.allCases.allSatisfy { $0.cursor != .crosshair && $0.cursor != .openHand }
                && Grip.left.cursor == .resizeLeftRight && Grip.top.cursor == .resizeUpDown
            print("\(arrows ? "PASS" : "FAIL")  each grip shows a resize arrow the ways it moves")
            // Drawn the right way up: the area clear, the screen just above it dimmed.
            var shown = false
            if let layer = InPlaceEditor.view?.layer,
               let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                       bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                // The view's layer is flipped (top-left origin) where it's shown; rendering on its own, the context is.
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                layer.render(in: context)
                if let drawn = context.makeImage() {
                    func red(_ point: CGPoint) -> Int {
                        guard let pixel = Capturer.cut(drawn, scale: 1, to: CGRect(origin: point, size: CGSize(width: 1, height: 1))),
                              let data = pixel.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return -1 }
                        return Int(bytes[0])
                    }
                    let inside = red(CGPoint(x: area.minX + 20, y: area.minY + 20))
                    // On a purple stripe inside the area, nothing orange over it (the edge's glow stays on the edge).
                    let purple = red(CGPoint(x: area.minX + 70, y: area.midY))
                    let above = red(CGPoint(x: area.minX + 20, y: area.minY - 20))
                    print("      area \(inside), above it \(above), purple inside \(purple)")
                    shown = inside > 200 && above < inside - 40 && purple < 185
                }
            }
            print("\(shown ? "PASS" : "FAIL")  the editor shows the area clear and the screen around it dimmed, the right way up")
            // Dragging: each step moves the area and the window shows it.
            let dragging = Date()
            for step in 1...120 {
                InPlaceEditor.area = area.offsetBy(dx: CGFloat(step % 60), dy: CGFloat(step % 40))
                InPlaceEditor.view?.window?.displayIfNeeded()
                CATransaction.flush()
            }
            print(String(format: "      a drag step takes %.2f ms", Date().timeIntervalSince(dragging) * 1000 / 120))
            InPlaceEditor.area = area
            // As in iShot: no tool at first, so the area can be dragged elsewhere; ⌘C then copies what's there now.
            let movable = InPlaceEditor.tool == nil
            let first = InPlaceEditor.picture(still, marks: [], area: InPlaceEditor.area ?? .zero, scale: 2)
            InPlaceEditor.area = area.offsetBy(dx: 50, dy: 0)
            let elsewhere = InPlaceEditor.picture(still, marks: [], area: InPlaceEditor.area ?? .zero, scale: 2)
            // The stripes are 50 pt wide: the area started on an orange one, and 50 pt on it starts on a purple one.
            let follows = movable && corner(first) == "orange" && corner(elsewhere) == "purple" && elsewhere.width == first.width
            print("\(follows ? "PASS" : "FAIL")  with no tool picked, the area can be dragged elsewhere, and the copy is what's there now")
            InPlaceEditor.cancel()
            // Esc while drawing goes back to picking the area (on the same screens), as in iShot; nothing is copied.
            var outcome: InPlaceEditor.Outcome?
            InPlaceEditor.open(screen: still, scale: 2, on: screen, area: area) { outcome = $0 }
            InPlaceEditor.finish(.back)
            var back = false
            if case .pickAgain = outcome { back = !InPlaceEditor.isOpen }
            print("\(back ? "PASS" : "FAIL")  Esc while drawing goes back to picking the area, copying nothing")
            if CommandLine.arguments.contains("--hold") { RunLoop.main.run(until: Date().addingTimeInterval(4)) }
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
            exit(ok && fills && tracks && quiet && adjustable && arrows && shown && follows && back && inside && !InPlaceEditor.isOpen ? 0 : 1)
        }
    }

    /// "orange" or "purple": the drawing test's stripe at a picture's top-left corner.
    private static func corner(_ image: CGImage) -> String {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Only the top-left pixel lands in the 1×1 context.
        context.draw(image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
        return pixel[0] > 200 ? "orange" : pixel[2] > 200 ? "purple" : "other"
    }

    /// Whether two pictures look the same: every pixel within 8 of 255 (antialiased edges round a little differently
    /// when drawn from another origin).
    private static func samePixels(_ a: CGImage?, _ b: CGImage?) -> Bool {
        guard let a, let b, a.width == b.width, a.height == b.height else { return false }
        func pixels(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return bytes
        }
        let x = pixels(a), y = pixels(b)
        var differ = 0, most = 0
        for i in x.indices where x[i] != y[i] { differ += 1; most = max(most, abs(Int(x[i]) - Int(y[i]))) }
        if most > 8 { print("      \(a.width)×\(a.height): \(differ) bytes differ, at most by \(most)") }
        return most <= 8
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
