import AppKit
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

    /// Each action's key combination; an action without one has no shortcut.
    @Published private(set) var shortcuts: [ShotAction: Shortcut] {
        didSet {
            let stored = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
            if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Keys.shortcuts) }
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

    private enum Keys {
        static let folder = "saveFolder"
        static let save = "saveToFolder"
        static let copy = "copyToClipboard"
        static let preview = "showPreview"
        static let sound = "playSound"
        static let shortcuts = "shortcuts"
        static let language = "language"
        static let appearance = "appearance"
        static let menuBarIcon = "showMenuBarIcon"
    }

    static var defaultFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    /// `live: false` for snapshots and the self-test: no hot keys, no captures.
    init(live: Bool = true, defaults: UserDefaults = .standard) {
        self.live = live
        self.defaults = defaults
        saveFolder = defaults.string(forKey: Keys.folder).map { URL(fileURLWithPath: $0) } ?? Self.defaultFolder
        saveToFolder = defaults.object(forKey: Keys.save) as? Bool ?? true
        copyToClipboard = defaults.object(forKey: Keys.copy) as? Bool ?? true
        showPreview = defaults.object(forKey: Keys.preview) as? Bool ?? true
        playSound = defaults.object(forKey: Keys.sound) as? Bool ?? true
        shortcuts = Self.loadShortcuts(defaults)
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .system
        let menuBarIcon = defaults.object(forKey: Keys.menuBarIcon) as? Bool ?? true
        showMenuBarIcon = menuBarIcon
        MainWindowRef.keepsDockIconWhenHidden = !menuBarIcon
        Localizer.language = language
        applyAppearance()
        guard live else { return }
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
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in ShotAction(rawValue: key).map { ($0, value) } })
    }

    // MARK: - Actions

    func perform(_ action: ShotAction) {
        switch action {
        case .captureArea:
            pick(.area, hint: L("Drag to capture  ·  Space: pick a window  ·  Esc: cancel"), text: false)
        case .captureWindow:
            pick(.window, hint: L("Click a window to capture it  ·  Space: drag an area  ·  Esc: cancel"), text: false)
        case .captureScreen:
            guard ready() else { return }
            let screen = Capturer.screenUnderPointer()
            run(.area(display: screen?.displayID ?? CGMainDisplayID(), rect: .null, scale: screen?.backingScaleFactor ?? 2),
                text: false)
        case .captureText:
            pick(.area, hint: L("Drag over text to copy it  ·  Esc: cancel"), text: true, allowsWindows: false)
        case .record:
            message(L("Screen recording is coming soon"), detail: L("It's the next part of %@ being built.", AppInfo.name),
                    symbol: "record.circle", tint: Theme.violet)
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
        if !MainWindowRef.show() { openWindow() }
    }

    /// Captures need Screen Recording; without it, ask and show where to turn it on.
    private func ready() -> Bool {
        guard live, !isBusy else { return false }
        refreshPermission()
        if hasPermission { return true }
        Capturer.requestPermission()
        tab = .general
        showWindow()
        return false
    }

    private func pick(_ mode: SelectionOverlay.Mode, hint: String, text: Bool, allowsWindows: Bool = true) {
        guard ready() else { return }
        PreviewPanel.shared.dismiss()
        SelectionOverlay.pick(mode, hint: hint, allowsWindows: allowsWindows) { [weak self] selection in
            guard let selection else { return }
            self?.run(selection, text: text)
        }
    }

    /// Takes the picture, then saves and copies it, or reads its text.
    private func run(_ selection: Selection, text: Bool) {
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                let (image, scale, screen) = try await grab(selection)
                if text {
                    await recognize(image, on: screen)
                } else {
                    deliver(image, scale: scale, on: screen)
                }
            } catch {
                message(L("Couldn't capture"), detail: error.localizedDescription, symbol: "exclamationmark.triangle.fill",
                        tint: Theme.amber)
            }
        }
    }

    private func grab(_ selection: Selection) async throws -> (CGImage, CGFloat, NSScreen?) {
        switch selection {
        case let .area(display, rect, scale):
            let screen = NSScreen.screens.first { $0.displayID == display }
            let image = try await Capturer.image(display: display, rect: rect.isNull ? nil : rect, scale: scale)
            return (image, scale, screen)
        case let .window(id):
            let (image, scale) = try await Capturer.image(window: id)
            return (image, scale, Capturer.screenUnderPointer())
        }
    }

    private func deliver(_ image: CGImage, scale: CGFloat, on screen: NSScreen?) {
        guard let png = Output.png(image, scale: scale) else { return }
        var file: URL?
        if saveToFolder {
            do {
                file = try Output.save(png, in: saveFolder, at: Date())
            } catch {
                message(L("Couldn't save"), detail: error.localizedDescription, symbol: "exclamationmark.triangle.fill", tint: Theme.amber)
            }
        }
        if copyToClipboard || file == nil { Output.copy(png: png, file: file) }
        lastFile = file
        lastPNG = file == nil ? png : nil
        if playSound { Self.shutter?.play() }
        if showPreview {
            PreviewPanel.shared.show(.init(thumbnail: PreviewPanel.thumbnail(image), png: png, file: file), on: screen)
        }
    }

    private func recognize(_ image: CGImage, on screen: NSScreen?) async {
        do {
            let lines = try await TextRecognizer.lines(in: image, vietnameseFirst: language == .vietnamese)
            guard !lines.isEmpty else {
                return message(L("No text found"), detail: L("Try a larger area, or text with more contrast."),
                               symbol: "text.viewfinder", tint: Theme.amber, on: screen)
            }
            Output.copy(text: lines.joined(separator: "\n"))
            message(lines.count == 1 ? L("Copied 1 line of text") : L("Copied %d lines of text", lines.count),
                    detail: lines.first, symbol: "text.viewfinder", tint: Theme.emerald, on: screen)
        } catch {
            message(L("Couldn't read the text"), detail: error.localizedDescription, symbol: "exclamationmark.triangle.fill",
                    tint: Theme.amber, on: screen)
        }
    }

    private func copyLast() {
        if let lastFile, let png = try? Data(contentsOf: lastFile) {
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

    /// The sound macOS plays for its own screenshots.
    private static let shutter = NSSound(contentsOfFile:
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        byReference: true)

    // MARK: - Shortcuts

    private func registerHotKeys() {
        hotKeys = [:]
        guard live, recording == nil else { return }
        var taken: Set<ShotAction> = []
        for (action, shortcut) in shortcuts where !action.isComingSoon {
            let hotKey = GlobalHotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, id: action.hotKeyID) { [weak self] in
                // Out of the Carbon handler first; picking an area runs its own event handling.
                DispatchQueue.main.async { self?.perform(action) }
            }
            if hotKey.isRegistered { hotKeys[action] = hotKey } else { taken.insert(action) }
        }
        takenShortcuts = taken
        systemShortcuts = Set(shortcuts.filter { !$0.key.isComingSoon && $0.value.isSystemShortcut }.map(\.key))
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
        resetShortcuts()
    }

    // MARK: - Snapshot / self-test support

    func simulate(permission: Bool, recording: ShotAction? = nil, error: (ShotAction, String)? = nil, system: Set<ShotAction> = []) {
        hasPermission = permission
        self.recording = recording
        shortcutError = error.map { ($0.0, $0.1) }
        systemShortcuts = system
    }

    // MARK: - Helpers

    private var appearanceObservation: NSKeyValueObservation?

    /// NSApp may not exist yet during launch, so apply on the next turn of the run loop.
    private func applyAppearance() {
        let appearance = appearance.nsAppearance
        DispatchQueue.main.async { [weak self] in
            guard let app = NSApp else { return }
            app.appearance = appearance
            Self.updateDockIcon()
            if self?.appearanceObservation == nil {
                self?.appearanceObservation = app.observe(\.effectiveAppearance) { _, _ in
                    DispatchQueue.main.async { Self.updateDockIcon() }
                }
            }
        }
    }

    /// The Dock icon is the dark tile in every appearance, like the app icon and the other LongoKit apps.
    private static func updateDockIcon() {
        NSApp?.applicationIconImage = Resource.image("Logo.png")
    }
}
