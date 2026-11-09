import AppKit
import ApplicationServices
import LongoKitUI
import ServiceManagement

enum MainTab: CaseIterable {
    case general, displays, about

    var title: String {
        switch self {
        case .general: return L("General")
        case .displays: return L("Displays")
        case .about: return L("About")
        }
    }
}

/// Manual: each display keeps the brightness you set. Sync: external displays follow the built-in one.
enum BrightnessMode: String, CaseIterable, Codable {
    case manual, sync

    var title: String {
        switch self {
        case .manual: return L("Manual")
        case .sync: return L("Sync")
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var displays: [Display] = []
    @Published var settings: [String: DisplaySettings] {
        didSet { save(settings, forKey: Keys.settings) }
    }
    @Published var mode: BrightnessMode {
        didSet {
            defaults.set(mode.rawValue, forKey: Keys.mode)
            if mode == .sync { lastBuiltin = nil; followBuiltin() }
        }
    }
    @Published var keysEnabled: Bool {
        didSet {
            defaults.set(keysEnabled, forKey: Keys.keys)
            startKeysIfPossible()
        }
    }

    @Published var tab: MainTab = .general
    /// The display whose page is open on the Displays tab.
    @Published var openDisplayKey: String?

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
    @Published private(set) var hasAccessibility = AXIsProcessTrusted()

    private let defaults: UserDefaults
    private let engine: DisplayEngine?
    private let keys = BrightnessKeys()
    private var syncTimer: Timer?
    private var permissionTimer: Timer?
    private var lastBuiltin: Double?
    /// Displays first seen this session: they keep whatever brightness they have until you change it.
    private var freshDisplays: Set<String> = []

    private enum Keys {
        static let settings = "displaySettings"
        static let mode = "brightnessMode"
        static let keys = "brightnessKeys"
        static let language = "language"
        static let appearance = "appearance"
        static let menuBarIcon = "showMenuBarIcon"
    }

    /// `live: false` for snapshots and the self-test: no display access, no event tap.
    init(live: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        engine = live ? DisplayEngine() : nil
        settings = (defaults.data(forKey: Keys.settings)).flatMap { try? JSONDecoder().decode([String: DisplaySettings].self, from: $0) } ?? [:]
        mode = defaults.string(forKey: Keys.mode).flatMap(BrightnessMode.init(rawValue:)) ?? .manual
        keysEnabled = defaults.object(forKey: Keys.keys) as? Bool ?? true
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .system
        let menuBarIcon = defaults.object(forKey: Keys.menuBarIcon) as? Bool ?? true
        showMenuBarIcon = menuBarIcon
        MainWindowRef.keepsDockIconWhenHidden = !menuBarIcon
        Localizer.language = language
        applyAppearance()
        guard let engine else { return }

        engine.onChange = { [weak self] in self?.reloadDisplays() }
        engine.onDDCBrightness = { [weak self] id, value in
            guard let self, let display = self.displays.first(where: { $0.id == id }),
                  self.freshDisplays.contains(display.key) else { return }
            self.settings[display.key]?.brightness = value
        }
        reloadDisplays()

        keys.handler = { [weak self] up in
            MainActor.assumeIsolated { self?.brightnessKey(up: up) ?? false }
        }
        startKeysIfPossible()

        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followBuiltin() }
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    // MARK: - Displays

    var builtin: Display? { displays.first(where: \.isBuiltin) }
    var externals: [Display] { displays.filter { !$0.isBuiltin } }

    func settings(for display: Display) -> DisplaySettings {
        settings[display.key] ?? DisplaySettings()
    }

    func displayName(_ display: Display) -> String {
        display.isBuiltin ? L("Built-in Display") : display.name
    }

    /// Sets one display's brightness (0…1).
    func setBrightness(_ value: Double, for display: Display) {
        update(display) { $0.brightness = min(max(value, 0), 1) }
    }

    func update(_ display: Display, _ change: (inout DisplaySettings) -> Void) {
        freshDisplays.remove(display.key)
        var value = settings(for: display)
        change(&value)
        settings[display.key] = value
        engine?.apply(value, to: display)
    }

    /// Presets set every display at once.
    func applyPreset(_ value: Double) {
        for display in displays { setBrightness(value, for: display) }
    }

    func resetDisplay(_ display: Display) {
        settings[display.key] = DisplaySettings()
        engine?.apply(DisplaySettings(), to: display)
    }

    private func reloadDisplays() {
        guard let engine else { return }
        engine.refresh()
        displays = engine.displays
        for display in displays {
            if settings[display.key] == nil {
                // A new display starts from what it shows now: macOS's value, the monitor's DDC reading
                // (arrives a moment later), or undimmed.
                var initial = DisplaySettings()
                initial.brightness = engine.currentBrightness(of: display) ?? 1
                settings[display.key] = initial
                freshDisplays.insert(display.key)
            } else if display.method != .native, !freshDisplays.contains(display.key) {
                // Saved displays get their brightness back; natively controlled ones keep macOS's.
                engine.apply(settings(for: display), to: display)
            }
        }
        if let key = openDisplayKey, !displays.contains(where: { $0.key == key }) { openDisplayKey = nil }
        followBuiltin()
    }

    /// Tracks the built-in display's brightness (it changes with the keys and ambient light); in Sync mode the
    /// external displays follow it.
    private func followBuiltin() {
        guard let engine, let builtin, let builtinValue = engine.builtinBrightness(),
              lastBuiltin.map({ abs($0 - builtinValue) > 0.004 }) ?? true else { return }
        lastBuiltin = builtinValue
        settings[builtin.key]?.brightness = builtinValue
        guard mode == .sync else { return }
        for display in externals {
            let value = settings(for: display)
            setBrightness(SyncMath.map(builtin: builtinValue, minimum: value.minimum, maximum: value.maximum), for: display)
        }
    }

    /// Brightness keys with the pointer on an external display change that display. Returns whether it did.
    private func brightnessKey(up: Bool) -> Bool {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
              let display = displays.first(where: { $0.id == id }),
              display.method != .native else { return false }
        let value = SyncMath.stepped(settings(for: display).brightness, up: up)
        setBrightness(value, for: display)
        BrightnessOSD.shared.show(value, on: display.id)
        return true
    }

    // MARK: - Permissions & startup

    var keysActive: Bool { keysEnabled && keys.isRunning }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func refreshPermissions() {
        let trusted = AXIsProcessTrusted()
        if trusted != hasAccessibility {
            hasAccessibility = trusted
            startKeysIfPossible()
        }
    }

    private func startKeysIfPossible() {
        guard keysEnabled, hasAccessibility, engine != nil else { return }
        keys.start()
        objectWillChange.send()
    }

    func setStartAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Start at login failed: \(error.localizedDescription)")
        }
        startAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Back to untouched displays: gamma restored, saved settings cleared.
    func restoreDefaults() {
        engine?.resetGamma()
        settings = [:]
        mode = .manual
        reloadDisplays()
    }

    /// Leaves the displays as macOS would have them.
    func prepareToQuit() {
        engine?.resetGamma()
    }

    // MARK: - Snapshot / self-test support

    func simulate(displays: [Display], settings: [String: DisplaySettings]) {
        self.displays = displays
        self.settings = settings
    }

    // MARK: - Helpers

    private var appearanceObservation: NSKeyValueObservation?

    /// NSApp may not exist yet during launch, so apply on the next turn of the run loop. The Dock icon follows:
    /// white tile in light mode, dark tile in dark mode.
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

    private static func updateDockIcon() {
        guard let app = NSApp else { return }
        let dark = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        app.applicationIconImage = Resource.image(dark ? "Logo.png" : "LogoLight.png")
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
