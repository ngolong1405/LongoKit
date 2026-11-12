import AppKit
import AVFoundation
import LongoKitUI
import ServiceManagement
import SwiftUI

enum MainTab: CaseIterable {
    case general, shortcuts, about

    var title: String {
        switch self {
        case .general: return L("General")
        case .shortcuts: return L("Shortcuts")
        case .about: return L("About")
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tab: MainTab = .general
    /// Paused, the shortcuts let go (other apps can use them meanwhile); the menu still captures.
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Keys.enabled)
            registerHotKeys()
        }
    }

    // Where captures go.
    @Published var saveFolder: URL {
        didSet { defaults.set(saveFolder.path, forKey: Keys.folder) }
    }
    @Published var saveToFolder: Bool {
        didSet {
            defaults.set(saveToFolder, forKey: Keys.save)
            if !saveToFolder && !copyToClipboard { copyToClipboard = true }
        }
    }
    @Published var copyToClipboard: Bool {
        didSet {
            defaults.set(copyToClipboard, forKey: Keys.copy)
            if !copyToClipboard && !saveToFolder { saveToFolder = true }
        }
    }
    @Published var showPreview: Bool {
        didSet { defaults.set(showPreview, forKey: Keys.preview) }
    }
    @Published var playSound: Bool {
        didSet { defaults.set(playSound, forKey: Keys.sound) }
    }
    /// The language text is read as: "auto" (any script) or one of Vision's codes. Picked in the text window.
    @Published var ocrLanguage: String {
        didSet { defaults.set(ocrLanguage, forKey: Keys.ocrLanguage) }
    }
    /// The last captures, newest first, for the menu's Recent list.
    @Published private(set) var history: [HistoryItem] = [] {
        didSet { if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: Keys.history) } }
    }
    @Published var keepHistory: Bool {
        didSet {
            defaults.set(keepHistory, forKey: Keys.keepHistory)
            if !keepHistory { clearHistory() }
        }
    }
    /// An area or the whole screen stays on screen to draw on, with a toolbar; it's saved and copied when Done is pressed.
    @Published var drawAfterCapture: Bool {
        didSet { defaults.set(drawAfterCapture, forKey: Keys.drawAfterCapture) }
    }

    // Screen recording.
    @Published var recordSystemAudio: Bool {
        didSet { defaults.set(recordSystemAudio, forKey: Keys.systemAudio) }
    }
    @Published var recordMicrophone: Bool {
        didSet {
            defaults.set(recordMicrophone, forKey: Keys.microphone)
            if recordMicrophone && live { requestMicrophone() }
        }
    }
    @Published var recordCursor: Bool {
        didSet { defaults.set(recordCursor, forKey: Keys.cursor) }
    }
    @Published var recordClicks: Bool {
        didSet { defaults.set(recordClicks, forKey: Keys.clicks) }
    }
    /// 30 or 60.
    @Published var recordFramesPerSecond: Int {
        didSet { defaults.set(recordFramesPerSecond, forKey: Keys.framesPerSecond) }
    }
    /// Counts 3, 2, 1 before a recording starts.
    @Published var recordCountdown: Bool {
        didSet { defaults.set(recordCountdown, forKey: Keys.countdown) }
    }
    @Published private(set) var isRecordingScreen = false
    @Published private(set) var isRecordingPaused = false
    /// 3, 2, 1 while counting down to a recording.
    @Published private(set) var countdown: Int?
    /// How long the current recording has run, for the menu bar and the recording bar.
    @Published private(set) var recordingSeconds = 0
    /// The microphone and showing clicks come with ScreenCaptureKit on macOS 15.
    static var canRecordMicrophone: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    /// Each action's key combination; an action without one has no shortcut.
    @Published private(set) var shortcuts: [ShotAction: Shortcut] {
        didSet {
            let stored = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
            if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Keys.shortcuts) }
            defaults.set(ShotAction.allCases.map(\.rawValue), forKey: Keys.shortcutActions)
        }
    }
    /// The action whose shortcut is being recorded; every shortcut is off meanwhile, so pressing one records it.
    @Published private(set) var recording: ShotAction?
    /// Why the last recorded combination wasn't taken.
    @Published private(set) var shortcutError: (action: ShotAction, text: String)?
    /// Shortcuts macOS wouldn't register (another app has them) and ones macOS uses itself.
    @Published private(set) var takenShortcuts: Set<ShotAction> = []
    @Published private(set) var systemShortcuts: Set<ShotAction> = []

    @Published var language: AppLanguage {
        didSet {
            Localizer.language = language
            defaults.set(language.rawValue, forKey: Keys.language)
        }
    }
    @Published var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            applyAppearance()
        }
    }
    @Published var showMenuBarIcon: Bool {
        didSet {
            defaults.set(showMenuBarIcon, forKey: Keys.menuBarIcon)
            MainWindowRef.keepsDockIconWhenHidden = !showMenuBarIcon
        }
    }
    @Published private(set) var startAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var hasPermission = Capturer.hasPermission
    /// A capture is under way: shortcuts pressed meanwhile are ignored.
    @Published private(set) var isBusy = false

    /// Opens the settings window when SwiftUI hasn't made it yet (set by the App).
    var openWindow: () -> Void = {}

    private let defaults: UserDefaults
    private let live: Bool
    private var hotKeys: [ShotAction: GlobalHotKey] = [:]
    private var activeObserver: Any?
    /// The last capture: its file, or the picture itself when it wasn't saved.
    private var lastFile: URL?
    private var lastPNG: Data?
    private var recorder: Recorder?
    private var recordingTimer: Timer?
    private var countdownTimer: Timer?
    /// Recorded time before the last pause, and when recording went on after it.
    private var recordedBeforePause: TimeInterval = 0
    private var recordingResumedAt: Date?
    private let recordingBar = RecordingBar()
    private let countdownPanel = CountdownPanel()

    private enum Keys {
        static let folder = "saveFolder"
        static let save = "saveToFolder"
        static let copy = "copyToClipboard"
        static let preview = "showPreview"
        static let sound = "playSound"
        static let ocrLanguage = "ocrLanguage"
        static let drawAfterCapture = "drawAfterCapture"
        static let history = "history"
        static let keepHistory = "keepHistory"
        static let shortcuts = "shortcuts"
        /// The actions there were when shortcuts were last saved: ones added since get their default.
        static let shortcutActions = "shortcutActions"
        static let language = "language"
        static let appearance = "appearance"
        static let menuBarIcon = "showMenuBarIcon"
        static let enabled = "enabled"
        static let systemAudio = "recordSystemAudio"
        static let microphone = "recordMicrophone"
        static let cursor = "recordCursor"
        static let clicks = "recordClicks"
        static let framesPerSecond = "recordFramesPerSecond"
        static let countdown = "recordCountdown"
    }

    /// Recordings made with saving off wait here, on the clipboard; macOS clears the folder in time.
    static var temporaryFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Longo Shot Recordings", isDirectory: true)
    }

    static var defaultFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    /// `live: false` for snapshots and the self-test: no hot keys, no captures.
    /// Where copies of clipboard-only captures are kept for the Recent list.
    private let historyFolder: URL

    init(live: Bool = true, defaults: UserDefaults = .standard, historyFolder: URL = History.defaultFolder) {
        self.live = live
        self.defaults = defaults
        self.historyFolder = historyFolder
        keepHistory = defaults.object(forKey: Keys.keepHistory) as? Bool ?? true
        history = defaults.data(forKey: Keys.history).flatMap { try? JSONDecoder().decode([HistoryItem].self, from: $0) } ?? []
        saveFolder = defaults.string(forKey: Keys.folder).map { URL(fileURLWithPath: $0) } ?? Self.defaultFolder
        saveToFolder = defaults.object(forKey: Keys.save) as? Bool ?? true
        copyToClipboard = defaults.object(forKey: Keys.copy) as? Bool ?? true
        showPreview = defaults.object(forKey: Keys.preview) as? Bool ?? true
        playSound = defaults.object(forKey: Keys.sound) as? Bool ?? true
        ocrLanguage = defaults.string(forKey: Keys.ocrLanguage) ?? "auto"
        drawAfterCapture = defaults.object(forKey: Keys.drawAfterCapture) as? Bool ?? true
        recordSystemAudio = defaults.object(forKey: Keys.systemAudio) as? Bool ?? false
        recordMicrophone = defaults.object(forKey: Keys.microphone) as? Bool ?? false
        recordCursor = defaults.object(forKey: Keys.cursor) as? Bool ?? true
        recordClicks = defaults.object(forKey: Keys.clicks) as? Bool ?? true
        recordFramesPerSecond = defaults.object(forKey: Keys.framesPerSecond) as? Int == 60 ? 60 : 30
        recordCountdown = defaults.object(forKey: Keys.countdown) as? Bool ?? true
        shortcuts = Self.loadShortcuts(defaults)
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .system
        let menuBarIcon = defaults.object(forKey: Keys.menuBarIcon) as? Bool ?? true
        showMenuBarIcon = menuBarIcon
        MainWindowRef.keepsDockIconWhenHidden = !menuBarIcon
        Localizer.language = language
        applyAppearance()
        guard live else { return }
        Sound.preload()
        InPlaceEditor.warmUp()
        registerHotKeys()
        // Screen Recording is granted in System Settings; look again whenever the app comes forward.
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermission() }
        }
    }

    private static func loadShortcuts(_ defaults: UserDefaults) -> [ShotAction: Shortcut] {
        guard let data = defaults.data(forKey: Keys.shortcuts),
              let stored = try? JSONDecoder().decode([String: Shortcut].self, from: data) else { return ShotAction.defaultShortcuts }
        if stored == ShotAction.defaults01 { return ShotAction.defaultShortcuts }
        var shortcuts = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in ShotAction(rawValue: key).map { ($0, value) } })
        // Saved before this list existed (0.1): every action since then is new.
        let known = Set(defaults.stringArray(forKey: Keys.shortcutActions) ?? Array(ShotAction.defaults01.keys) + ["copyLast", "openFolder"])
        for action in ShotAction.allCases where !known.contains(action.rawValue) {
            if let shortcut = action.defaultShortcut, !shortcuts.values.contains(shortcut) { shortcuts[action] = shortcut }
        }
        return shortcuts
    }

    // MARK: - Actions

    func perform(_ action: ShotAction) {
        switch action {
        case .captureArea:
            // A double click (or Return) takes the whole screen, like Capture Full Screen.
            // One pick for both: drag an area, click the highlighted window, or double-click for the whole screen.
            pick(.area, hint: L("Drag an area  ·  Click a window  ·  Double-click: whole screen  ·  Esc: cancel"), text: false,
                 allowsScreen: true, draw: drawAfterCapture, windowsOnClick: true)
        case .captureScreen:
            guard ready() else { return }
            let clear = !Capturer.panelsShowing
            PreviewPanel.shared.dismiss()
            let screen = Capturer.screenUnderPointer()
            // The screen as it is, in one quick call; the capture is cut from it.
            if let screen, clear,
               let still = Capturer.instant(display: screen.displayID, pointWidth: screen.frame.width) {
                frozen = [screen.displayID: still]
            }
            run(.area(display: screen?.displayID ?? CGMainDisplayID(), rect: .null, scale: screen?.backingScaleFactor ?? 2),
                text: false, draw: drawAfterCapture)
        case .captureText:
            pick(.area, hint: L("Drag over text to copy it  ·  Esc: cancel"), text: true, allowsWindows: false)
        case .record:
            if countdown != nil {
                cancelCountdown()
            } else if isRecordingScreen {
                stopRecording()
            } else {
                // The dragged area stays to adjust, with Start in a toolbar under it; a double click takes the screen.
                let adjusting = SelectionOverlay.Adjusting(
                    hint: L("Drag the area or its corners to adjust  ·  ↩: start  ·  Esc: cancel")
                ) { [weak self] send in fixedHostingView(RecordToolbar(send: send).environmentObject(self!)) }
                pick(.area, hint: L("Drag an area to record  ·  Double-click: whole screen  ·  Space: pick a window  ·  Esc: cancel"),
                     allowsScreen: true, adjusting: adjusting) { [weak self] selection in self?.startRecording(selection) }
            }
        case .pauseRecording:
            if isRecordingScreen {
                togglePause()
            } else if countdown == nil {
                message(L("Nothing is being recorded"), detail: shortcuts[.record].map { L("Start a recording with %@.", $0.symbols) },
                        symbol: "pause.circle", tint: Theme.amber)
            }
        case .annotateLast:
            annotateLast()
        case .copyLast:
            copyLast()
        case .openFolder:
            try? FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(saveFolder)
        case .openSettings:
            showWindow()
        }
    }

    func showWindow() {
        if !MainWindowRef.show(module: ShotModule.id) { openWindow() }
    }

    /// Captures need Screen Recording; without it, ask and show where to turn it on.
    private func ready() -> Bool {
        guard live, !isBusy, !InPlaceEditor.isOpen else { return false }
        refreshPermission()
        if hasPermission { return true }
        Capturer.requestPermission()
        tab = .general
        showWindow()
        return false
    }

    /// Screens as they were when a capture's shortcut was pressed; an area picked is cut from these.
    private var frozen: [CGDirectDisplayID: (image: CGImage, scale: CGFloat)] = [:]
    /// The screens the area being drawn on was picked on, for picking again.
    private var pickedOn: [CGDirectDisplayID: (image: CGImage, scale: CGFloat)] = [:]

    /// Esc while drawing on a capture: back to picking the area, on the same frozen screens, as in iShot.
    private func pickAgain() {
        let screens = pickedOn
        pickedOn = [:]
        // Without them, the screens are taken again leaving Shot's windows out: the editor just put away can still
        // be on screen for a moment, and a quick capture would have it in.
        pick(.area, hint: L("Drag an area  ·  Click a window  ·  Double-click: whole screen  ·  Esc: cancel"), text: false,
             allowsScreen: true, draw: drawAfterCapture, windowsOnClick: true, reuse: screens, leavingOutPanels: true)
    }

    /// A picture (or its text). The overlay comes up at once; the screens are frozen meanwhile and slipped under it
    /// (they look the same), so a menu or popover open when the shortcut is pressed is still there after the first
    /// click closes it. A pick made before they're in is captured live.
    /// `reuse`: screens already frozen, to pick on them again.
    private func pick(_ mode: SelectionOverlay.Mode, hint: String, text: Bool, allowsWindows: Bool = true, allowsScreen: Bool = false,
                      draw: Bool = false, windowsOnClick: Bool = false,
                      reuse: [CGDirectDisplayID: (image: CGImage, scale: CGFloat)] = [:], leavingOutPanels: Bool = false) {
        guard ready(), !SelectionOverlay.isPicking else { return }
        if !reuse.isEmpty {
            frozen = reuse
            pick(mode, hint: hint, allowsWindows: allowsWindows, allowsScreen: allowsScreen, windowsOnClick: windowsOnClick,
                 frozen: reuse) { [weak self] selection in
                self?.run(selection, text: text, draw: draw)
            }
            return
        }
        // A panel of Shot's on screen (the last capture's preview) could still be in a quick capture taken right after
        // it's put away: then ScreenCaptureKit, which leaves it out.
        let clear = !leavingOutPanels && !Capturer.panelsShowing
        PreviewPanel.shared.dismiss()
        // As iShot does: the screens as they are, in one quick call each, then the overlay on them.
        if clear, let still = Capturer.freezeNow() {
            frozen = still
            pick(mode, hint: hint, allowsWindows: allowsWindows, allowsScreen: allowsScreen, windowsOnClick: windowsOnClick,
                 frozen: still) { [weak self] selection in
                self?.run(selection, text: text, draw: draw)
            }
            return
        }
        frozen = [:]
        pick(mode, hint: hint, allowsWindows: allowsWindows, allowsScreen: allowsScreen, windowsOnClick: windowsOnClick) { [weak self] selection in
            self?.run(selection, text: text, draw: draw)
        }
        guard SelectionOverlay.isPicking else { return }
        Task { @MainActor in
            let still = await Capturer.freeze()
            // Only for the pick still under way.
            guard SelectionOverlay.isPicking else { return }
            frozen = still
            SelectionOverlay.supply(still)
        }
    }

    private func pick(_ mode: SelectionOverlay.Mode, hint: String, allowsWindows: Bool = true, allowsScreen: Bool = false,
                      adjusting: SelectionOverlay.Adjusting? = nil, windowsOnClick: Bool = false,
                      frozen: [CGDirectDisplayID: (image: CGImage, scale: CGFloat)] = [:],
                      then use: @escaping (Selection) -> Void) {
        guard ready() else { return }
        PreviewPanel.shared.dismiss()
        SelectionOverlay.pick(mode, hint: hint, allowsWindows: allowsWindows, allowsScreen: allowsScreen,
                              adjusting: adjusting, windowsOnClick: windowsOnClick, frozen: frozen) { [weak self] selection in
            if let selection { use(selection) } else { self?.frozen = [:] }
        }
    }

    /// Takes the picture, then saves and copies it, or reads its text.
    /// `draw`: an area, the screen or a window is drawn on in place first, and only saved and copied when that's done.
    private func run(_ selection: Selection, text: Bool, draw: Bool = false) {
        // The shutter (not for copying text); nothing on screen, it's quick.
        if !text { Sound.shutter.play(if: playSound) }
        // No editor takes the overlay's place: it goes now (it's left out of captures either way).
        if !draw || text { SelectionOverlay.dismissLingering() }
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                // An area (or the screen) to draw on: the editor gets the whole screen, so the area can still change.
                if draw, !text, case let .area(display, rect, scale) = selection,
                   let screen = NSScreen.screens.first(where: { $0.displayID == display }) {
                    let still = frozen[display]
                    // Kept for Esc, which goes back to picking on the same screens.
                    if !frozen.isEmpty { pickedOn = frozen }
                    frozen = [:]
                    let full: CGImage
                    if let still { full = still.image } else { full = try await Capturer.image(display: display, rect: nil, scale: scale) }
                    let fullScale = still?.scale ?? scale
                    InPlaceEditor.open(screen: full, scale: fullScale, on: screen, area: rect) { [weak self] outcome in
                        self?.finishDrawing(outcome, scale: fullScale, on: screen)
                    }
                    return
                }
                // A window to draw on in place is taken without its shadow, to sit exactly on its frame.
                var place: (NSScreen, CGRect)?
                if draw, case let .window(id) = selection { place = Capturer.place(of: id) }
                let (image, scale, screen) = try await grab(selection, shadow: place == nil)
                // Kept for Esc, which goes back to picking on the same screens.
                if draw, !frozen.isEmpty { pickedOn = frozen }
                frozen = [:]
                if case let .area(_, rect, _) = selection, let screen { place = (screen, rect) }
                if text {
                    recognize(image, scale: scale, on: screen)
                } else if draw, let (screen, rect) = place {
                    InPlaceEditor.open(image, scale: scale, on: screen, area: rect) { [weak self] outcome in
                        self?.finishDrawing(outcome, scale: scale, on: screen)
                    }
                } else {
                    deliver(image, scale: scale, on: screen)
                }
            } catch {
                message(L("Couldn't capture"), detail: error.localizedDescription, symbol: "exclamationmark.triangle.fill",
                        tint: Theme.amber)
            }
        }
    }

    private func finishDrawing(_ outcome: InPlaceEditor.Outcome, scale: CGFloat, on screen: NSScreen) {
        switch outcome {
        case let .save(drawn): deliver(drawn, scale: scale, on: screen)
        case let .saveAndCopy(drawn): deliver(drawn, scale: scale, on: screen, copy: true)
        case .pickAgain: pickAgain()
        case .discard: break
        }
    }

    private func grab(_ selection: Selection, shadow: Bool = true) async throws -> (CGImage, CGFloat, NSScreen?) {
        switch selection {
        case let .area(display, rect, scale):
            let screen = NSScreen.screens.first { $0.displayID == display }
            // Cut from the frozen screen when there is one: what was there when the shortcut was pressed.
            if let still = frozen[display], let image = Capturer.cut(still.image, scale: still.scale, to: rect) {
                return (image, still.scale, screen)
            }
            let image = try await Capturer.image(display: display, rect: rect.isNull ? nil : rect, scale: scale)
            return (image, scale, screen)
        case let .window(id):
            if let (image, scale) = Capturer.instant(window: id, shadow: shadow) {
                return (image, scale, Capturer.screenUnderPointer())
            }
            let (image, scale) = try await Capturer.image(window: id, shadow: shadow)
            return (image, scale, Capturer.screenUnderPointer())
        }
    }

    /// Saves (when saving is on and `save`) and copies a capture, then shows it in the corner. `save: false` is the
    /// clipboard only, whatever the setting; `copy: true` copies even with copying off.
    private func deliver(_ image: CGImage, scale: CGFloat, on screen: NSScreen?, save: Bool = true, copy: Bool = false) {
        // Encoding a Retina screen as PNG takes a few hundred ms and the file is megabytes: that happens off the main
        // thread, so nothing on screen stutters, then the rest follows.
        let folder = saveToFolder && save ? saveFolder : nil
        let date = Date()
        // On the clipboard at once (pasting right away works); the PNG and the file follow.
        let clipboard = copyToClipboard || copy || folder == nil ? Output.promise(image, scale: scale) : nil
        Task { @MainActor in
            let (png, file, failure) = await Task.detached(priority: .userInitiated) { () -> (Data?, URL?, String?) in
                guard let png = Output.png(image, scale: scale) else { return (nil, nil, nil) }
                guard let folder else { return (png, nil, nil) }
                do {
                    return (png, try Output.save(png, in: folder, at: date), nil)
                } catch {
                    return (png, nil, error.localizedDescription)
                }
            }.value
            guard let png else { return }
            if let failure {
                message(L("Couldn't save"), detail: failure, symbol: "exclamationmark.triangle.fill", tint: Theme.amber)
            }
            finishDelivery(image, png: png, file: file, on: screen, copy: copy, clipboard: clipboard)
        }
    }

    private func finishDelivery(_ image: CGImage, png: Data, file: URL?, on screen: NSScreen?, copy: Bool, clipboard: Int?) {
        let copied = copyToClipboard || copy || file == nil
        // The finished picture and its file take the promise's place, unless something else was copied since.
        if copied && (clipboard == nil || NSPasteboard.general.changeCount == clipboard) { Output.copy(png: png, file: file) }
        lastFile = file
        lastPNG = file == nil ? png : nil
        remember(file: file, png: png)
        if showPreview {
            PreviewPanel.shared.show(.init(thumbnail: PreviewPanel.thumbnail(image), png: png, file: file,
                                           showsInFinder: file != nil, copied: copied) { [weak self] in
                guard let self else { return }
                Annotator.open(png: png, file: file, model: self)
            }, on: screen)
        }
    }

    /// The text in the picked area, in a window to check, edit and copy, as iShot does: the picture, the language it's
    /// read as, the text, Copy (⌘↩).
    private func recognize(_ image: CGImage, scale: CGFloat, on screen: NSScreen?) {
        let reading = TextReading(image, language: ocrLanguage, vietnameseFirst: language == .vietnamese) { [weak self] picked in
            self?.ocrLanguage = picked
        }
        TextWindow.open(reading, scale: scale, on: screen) { [weak self] text in
            guard let self else { return }
            Output.copy(text: text)
            Sound.text.play(if: playSound)
            message(L("Text copied"), detail: text.components(separatedBy: "\n").first, symbol: "text.viewfinder",
                    tint: Theme.emerald, on: screen)
        }
    }

    // MARK: - Recording

    private func startRecording(_ selection: Selection) {
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            let saved = saveToFolder
            let folder = saved ? saveFolder : Self.temporaryFolder
            var options = Recorder.Options(framesPerSecond: recordFramesPerSecond, systemAudio: recordSystemAudio,
                                           showsCursor: recordCursor, showsClicks: recordClicks)
            options.microphone = recordMicrophone && Self.canRecordMicrophone
                && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = Output.freeURL(in: folder, name: Output.fileName(at: Date(), extension: "mp4"))
                let recorder = try await Recorder.start(selection, options: options, to: url, paused: recordCountdown)
                // macOS can end the stream itself, e.g. when the recorded window closes: keep what was recorded.
                recorder.onStop = { [weak self] _ in DispatchQueue.main.async { self?.stopRecording() } }
                self.recorder = recorder
                if recordCountdown { count(down: selection) } else { begin(selection) }
            } catch {
                message(L("Couldn't start recording"), detail: error.localizedDescription,
                        symbol: "exclamationmark.triangle.fill", tint: Theme.amber)
            }
        }
    }

    /// 3, 2, 1 over the area, then recording starts. The stream is already running (paused), so it starts at once.
    private func count(down selection: Selection) {
        let (screen, area) = place(selection)
        countdown = 3
        Sound.tick.play(if: playSound)
        if let screen { countdownPanel.show(on: screen, area: area, model: self) }
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, let count = self.countdown else { return timer.invalidate() }
                if count > 1 {
                    self.countdown = count - 1
                    Sound.tick.play(if: self.playSound)
                } else {
                    timer.invalidate()
                    self.countdownTimer = nil
                    self.countdown = nil
                    self.countdownPanel.hide()
                    self.recorder?.resume()
                    self.begin(selection)
                }
            }
        }
    }

    /// The record shortcut during the countdown: nothing is recorded and no file is left behind.
    private func cancelCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdown = nil
        countdownPanel.hide()
        guard let recorder else { return }
        self.recorder = nil
        Task { if let url = try? await recorder.stop() { try? FileManager.default.removeItem(at: url) } }
    }

    /// The timer and the recording bar.
    private func begin(_ selection: Selection) {
        Sound.start.play(if: playSound)
        isRecordingScreen = true
        isRecordingPaused = false
        recordingSeconds = 0
        recordedBeforePause = 0
        recordingResumedAt = Date()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateRecordingTime() }
        }
        let (screen, area) = place(selection)
        if let screen { recordingBar.show(on: screen, area: area, model: self) }
    }

    private func updateRecordingTime() {
        let running = recordingResumedAt.map { Date().timeIntervalSince($0) } ?? 0
        let seconds = Int(recordedBeforePause + running)
        if seconds != recordingSeconds { recordingSeconds = seconds }
    }

    private func togglePause() {
        guard let recorder else { return }
        if isRecordingPaused {
            recorder.resume()
            recordingResumedAt = Date()
        } else {
            recorder.pause()
            recordedBeforePause += recordingResumedAt.map { Date().timeIntervalSince($0) } ?? 0
            recordingResumedAt = nil
        }
        isRecordingPaused.toggle()
        (isRecordingPaused ? Sound.pause : Sound.resume).play(if: playSound)
        updateRecordingTime()
    }

    /// The screen a selection is on, and the area on it (nil for a whole screen or a window).
    private func place(_ selection: Selection) -> (NSScreen?, CGRect?) {
        switch selection {
        case let .area(display, rect, _):
            return (NSScreen.screens.first { $0.displayID == display } ?? NSScreen.main, rect.isNull ? nil : rect)
        case .window:
            return (Capturer.screenUnderPointer(), nil)
        }
    }

    /// Quitting while recording finishes the file first.
    func finishRecording(then done: @escaping () -> Void) {
        if countdown != nil { cancelCountdown() }
        guard isRecordingScreen else { return done() }
        stopRecording(then: done)
    }

    private func stopRecording(then done: @escaping () -> Void = {}) {
        guard let recorder else { return done() }
        self.recorder = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecordingScreen = false
        isRecordingPaused = false
        recordingResumedAt = nil
        recordingBar.hide()
        Sound.stop.play(if: playSound)
        let screen = Capturer.screenUnderPointer()
        Task { @MainActor in
            defer { done() }
            do {
                let url = try await recorder.stop()
                await deliverMovie(url, saved: url.deletingLastPathComponent() != Self.temporaryFolder, on: screen)
            } catch {
                message(L("Couldn't save the recording"), detail: error.localizedDescription,
                        symbol: "exclamationmark.triangle.fill", tint: Theme.amber, on: screen)
            }
        }
    }

    private func deliverMovie(_ url: URL, saved: Bool, on screen: NSScreen?) async {
        if copyToClipboard || !saved { Output.copy(file: url) }
        lastFile = url
        lastPNG = nil
        let thumbnail = await Output.movieThumbnail(url)
        if keepHistory {
            add(HistoryItem(file: url, isMovie: true, cached: !saved, duration: thumbnail?.1))
        }
        guard showPreview, let (thumbnail, duration) = thumbnail else {
            return message(saved ? L("Recording saved") : L("Recording copied"), detail: url.lastPathComponent,
                           symbol: "record.circle", tint: Theme.emerald, on: screen)
        }
        PreviewPanel.shared.show(.init(thumbnail: thumbnail, png: nil, file: url, showsInFinder: saved,
                                       badge: RecordingBar.time(duration), copied: copyToClipboard || !saved), on: screen)
    }

    private func requestMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { if !granted { self.recordMicrophone = false } }
            }
        default:
            recordMicrophone = false
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }

    /// The last capture in the drawing window; recordings can't be drawn on.
    private func annotateLast() {
        if let lastFile, lastFile.pathExtension == "png", let png = try? Data(contentsOf: lastFile) {
            Annotator.open(png: png, file: lastFile, model: self)
        } else if let lastPNG {
            Annotator.open(png: lastPNG, file: nil, model: self)
        } else {
            message(lastFile == nil ? L("Nothing captured yet") : L("Only screenshots can be drawn on"),
                    symbol: "pencil.tip.crop.circle", tint: Theme.amber)
        }
    }

    /// Done in the drawing window: the drawn picture replaces the capture's file and goes on the clipboard.
    func annotated(_ png: Data, file: URL?) {
        if let file {
            do {
                try png.write(to: file, options: .atomic)
            } catch {
                return message(L("Couldn't save"), detail: error.localizedDescription, symbol: "exclamationmark.triangle.fill", tint: Theme.amber)
            }
        }
        if copyToClipboard || file == nil { Output.copy(png: png, file: file) }
        lastFile = file
        lastPNG = file == nil ? png : nil
        if let file, let index = history.firstIndex(where: { $0.file == file }) {
            // Same file, new picture: a new id makes its thumbnail again.
            HistoryThumbnails.shared.forget(history[index])
            history[index].id = UUID()
        } else {
            remember(file: file, png: png)
        }
        message(file != nil ? L("Drawing saved") : L("Drawing copied"), detail: file?.lastPathComponent,
                symbol: "pencil.tip.crop.circle", tint: Theme.emerald)
    }

    // MARK: - Recent

    /// A screenshot for the Recent list: its saved file, or else a copy of it in the cache.
    func remember(file: URL?, png: Data) {
        guard keepHistory else { return }
        if let file { return add(HistoryItem(file: file, isMovie: false, cached: false)) }
        let copy = historyFolder.appendingPathComponent(UUID().uuidString + ".png")
        let folder = historyFolder
        // Written before `add` can drop (and delete) it: both go through the same queue, in order.
        History.files.async {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? png.write(to: copy, options: .atomic)
        }
        add(HistoryItem(file: copy, isMovie: false, cached: true))
    }

    private func add(_ item: HistoryItem) {
        let (kept, dropped) = History.adding(item, to: history)
        history = kept
        History.deleteCached(dropped)
    }

    /// Captures whose files are gone (deleted or moved) leave the list. Run when the menu opens.
    func pruneHistory() {
        let missing = history.filter { !$0.exists }
        guard !missing.isEmpty else { return }
        history.removeAll { item in missing.contains { $0.id == item.id } }
    }

    func copy(_ item: HistoryItem) {
        if item.isMovie {
            Output.copy(file: item.file)
        } else if let png = try? Data(contentsOf: item.file) {
            Output.copy(png: png, file: item.cached ? nil : item.file)
        }
    }

    func open(_ item: HistoryItem) {
        NSWorkspace.shared.open(item.file)
    }

    func showInFinder(_ item: HistoryItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.file])
    }

    /// The drawing window; a cached copy comes back as a new capture, a saved file is drawn over.
    func draw(_ item: HistoryItem) {
        guard !item.isMovie, let png = try? Data(contentsOf: item.file) else { return }
        Annotator.open(png: png, file: item.cached ? nil : item.file, model: self)
    }

    func remove(_ item: HistoryItem) {
        history.removeAll { $0.id == item.id }
        HistoryThumbnails.shared.forget(item)
        History.deleteCached([item])
    }

    func clearHistory() {
        let all = history
        history = []
        History.deleteCached(all)
        // Copies left by older lists, too.
        let folder = historyFolder
        DispatchQueue.global(qos: .utility).async { try? FileManager.default.removeItem(at: folder) }
    }

    private func copyLast() {
        if let lastFile, lastFile.pathExtension != "png", FileManager.default.fileExists(atPath: lastFile.path) {
            Output.copy(file: lastFile)
        } else if let lastFile, let png = try? Data(contentsOf: lastFile) {
            Output.copy(png: png, file: lastFile)
        } else if let lastPNG {
            Output.copy(png: lastPNG, file: nil)
        } else {
            return message(L("Nothing captured yet"), symbol: "doc.on.clipboard", tint: Theme.amber)
        }
        message(L("Last capture copied"), symbol: "doc.on.clipboard", tint: Theme.emerald)
    }

    private func message(_ title: String, detail: String? = nil, symbol: String, tint: Color, on screen: NSScreen? = nil) {
        guard live else { return }
        PreviewPanel.shared.message(title, detail: detail, symbol: symbol, tint: tint, on: screen ?? Capturer.screenUnderPointer())
    }

    // MARK: - Shortcuts

    private func registerHotKeys() {
        hotKeys = [:]
        guard live, isEnabled, recording == nil else { return }
        var taken: Set<ShotAction> = []
        for (action, shortcut) in shortcuts {
            let hotKey = GlobalHotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
                // Out of the Carbon handler first; picking an area runs its own event handling.
                DispatchQueue.main.async { self?.perform(action) }
            }
            if hotKey.isRegistered { hotKeys[action] = hotKey } else { taken.insert(action) }
        }
        takenShortcuts = taken
        systemShortcuts = Set(shortcuts.filter { $0.value.isSystemShortcut }.map(\.key))
    }

    func beginRecording(_ action: ShotAction) {
        shortcutError = nil
        recording = action
        hotKeys = [:]
    }

    func endRecording() {
        guard recording != nil else { return }
        recording = nil
        registerHotKeys()
    }

    /// Takes a recorded combination for an action. Returns false (with `shortcutError` set) when it can't be used.
    @discardableResult
    func setShortcut(_ shortcut: Shortcut, for action: ShotAction) -> Bool {
        if !shortcut.isAllowed {
            shortcutError = (action, L("Add ⌘, ⌥, ⌃ or ⇧ to the key (F1–F19 work on their own)."))
            return false
        }
        if let other = shortcuts.first(where: { $0.key != action && $0.value == shortcut })?.key {
            shortcutError = (action, L("%@ already uses %@.", other.title, shortcut.symbols))
            return false
        }
        shortcutError = nil
        shortcuts[action] = shortcut
        if recording == nil { registerHotKeys() }
        return true
    }

    func clearShortcut(_ action: ShotAction) {
        shortcutError = nil
        shortcuts[action] = nil
        if recording == nil { registerHotKeys() }
    }

    func resetShortcuts() {
        shortcutError = nil
        shortcuts = ShotAction.defaultShortcuts
        registerHotKeys()
    }

    // MARK: - Settings

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveFolder
        panel.prompt = L("Choose")
        panel.message = L("Captures are saved in this folder.")
        if panel.runModal() == .OK, let url = panel.url { saveFolder = url }
    }

    func refreshPermission() {
        let granted = Capturer.hasPermission
        if granted != hasPermission { hasPermission = granted }
    }

    func requestPermission() {
        Capturer.requestPermission()
        Capturer.openPermissionSettings()
    }

    func setStartAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Start at login failed: \(error.localizedDescription)")
        }
        startAtLogin = SMAppService.mainApp.status == .enabled
    }

    func restoreDefaults() {
        saveFolder = Self.defaultFolder
        saveToFolder = true
        copyToClipboard = true
        showPreview = true
        playSound = true
        drawAfterCapture = true
        keepHistory = true
        recordSystemAudio = false
        recordMicrophone = false
        recordCursor = true
        recordClicks = true
        recordFramesPerSecond = 30
        recordCountdown = true
        resetShortcuts()
    }

    // MARK: - Snapshot / self-test support

    func simulate(permission: Bool, recording: ShotAction? = nil, error: (ShotAction, String)? = nil, system: Set<ShotAction> = [],
                  recordingScreen: Int? = nil, paused: Bool = false, countdown: Int? = nil) {
        hasPermission = permission
        isRecordingScreen = recordingScreen != nil
        isRecordingPaused = paused
        recordingSeconds = recordingScreen ?? 0
        self.countdown = countdown
        self.recording = recording
        shortcutError = error.map { ($0.0, $0.1) }
        systemShortcuts = system
    }

    // MARK: - Helpers

    /// NSApp may not exist yet during launch, so apply on the next turn of the run loop.
    private func applyAppearance() {
        let appearance = appearance.nsAppearance
        // The Dock shows the bundle's icon, the dark tile in every appearance. Setting applicationIconImage too
        // would keep a decoded copy of the logo (~8 MB) alive for the app's whole life.
        DispatchQueue.main.async { NSApp?.appearance = appearance }
    }
}
