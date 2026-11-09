import AppKit
import ApplicationServices
import Carbon.HIToolbox
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

/// How a display that's turned off is off.
enum PowerOff: String, Codable {
    /// Disabled in macOS, as if unplugged.
    case disabled
    /// macOS refused: the picture is made black instead.
    case blackout
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
    /// Displays turned off by key. Saved before each change, so a crash can't leave a display off.
    @Published private(set) var powerOff: [String: PowerOff] {
        didSet { save(powerOff, forKey: Keys.powerOff) }
    }
    /// Each turned-off display as it was when turned off: its ID is how macOS turns it back on, and it stays listed
    /// (as Off) even if it drops out of the connected list. Saved, for turning it back on after a crash.
    private var offDisplays: [String: Display] {
        didSet { save(offDisplays, forKey: Keys.offDisplays) }
    }
    /// Turned-off displays asked to come back on; forgotten once they show a picture.
    private var turningOn: Set<String> = []
    /// Paused, the app leaves displays alone: no Sync, no brightness keys, no software dimming.
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            if isEnabled {
                lastBuiltin = nil
                switchedControl()
            } else {
                engine?.resetGamma()
                reloadDisplays()
            }
        }
    }
    @Published var keysEnabled: Bool {
        didSet {
            defaults.set(keysEnabled, forKey: Keys.keys)
            startKeysIfPossible()
        }
    }

    /// DDC displays that gave no valid answer: their port may not pass DDC on (e.g. a MacBook's HDMI port).
    @Published private(set) var silentDDC: Set<String> = []

    /// The Mac's output volume, for the built-in display's speaker slider; nil when the output has no volume.
    @Published private(set) var systemVolume: Double? = nil

    @Published var tab: MainTab = .general {
        // Coming back to Displays from another tab starts at the list, not the display open before.
        didSet { if tab != oldValue { openDisplayKey = nil } }
    }
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
    private var emergencyKey: GlobalHotKey?
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
        static let powerOff = "displaysTurnedOff"
        static let offDisplays = "turnedOffDisplays"
        static let enabled = "enabled"
    }

    /// `live: false` for snapshots and the self-test: no display access, no event tap.
    init(live: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        engine = live ? DisplayEngine() : nil
        settings = (defaults.data(forKey: Keys.settings)).flatMap { try? JSONDecoder().decode([String: DisplaySettings].self, from: $0) } ?? [:]
        offDisplays = (defaults.data(forKey: Keys.offDisplays)).flatMap { try? JSONDecoder().decode([String: Display].self, from: $0) } ?? [:]
        powerOff = (defaults.data(forKey: Keys.powerOff)).flatMap { try? JSONDecoder().decode([String: PowerOff].self, from: $0) } ?? [:]
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
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

        // Displays left off by a previous run come back on first; each is forgotten once it shows a picture.
        engine.turnedOff = Set(powerOff.keys)
        if !powerOff.isEmpty { turnAllOn() }
        emergencyKey = GlobalHotKey(controlOptionCommand: kVK_ANSI_B, id: 1) { [weak self] in
            MainActor.assumeIsolated { self?.turnAllOn() }
        }

        engine.onChange = { [weak self] in self?.reloadDisplays() }
        engine.onDDCBrightness = { [weak self] id, value in
            guard let self, let display = self.displays.first(where: { $0.id == id }),
                  self.freshDisplays.contains(display.key) else { return }
            self.settings[display.key]?.brightness = value
        }
        engine.onDDCSilent = { [weak self] id in
            guard let self, let display = self.displays.first(where: { $0.id == id }) else { return }
            self.silentDDC.insert(display.key)
        }
        engine.onDDCVolume = { [weak self] id, value in
            guard let self, let display = self.displays.first(where: { $0.id == id }),
                  self.settings(for: display).volume == nil else { return }
            self.settings[display.key, default: DisplaySettings()].volume = value
        }
        reloadDisplays()

        keys.handler = { [weak self] up in
            MainActor.assumeIsolated { self?.brightnessKey(up: up) ?? false }
        }
        startKeysIfPossible()

        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.followBuiltin()
                self?.refreshSystemVolume()
            }
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    // MARK: - Displays

    var builtin: Display? { displays.first(where: \.isBuiltin) }
    var externals: [Display] { displays.filter { !$0.isBuiltin } }

    func isOn(_ display: Display) -> Bool { powerOff[display.key] == nil }

    func settings(for display: Display) -> DisplaySettings {
        settings[display.key] ?? DisplaySettings()
    }

    func displayName(_ display: Display) -> String {
        display.isBuiltin ? L("Built-in Display") : display.name
    }

    /// Sets one display's brightness (0…1).
    func setBrightness(_ value: Double, for display: Display) {
        setLevel(min(max(value, 0), 1), for: display)
    }

    /// The range an external display moves through in Sync, as the built-in display goes from 0% to 100%.
    func setSyncRange(_ minimum: Double, _ maximum: Double, for display: Display) {
        settings[display.key, default: DisplaySettings()].minimum = min(minimum, maximum)
        settings[display.key, default: DisplaySettings()].maximum = max(minimum, maximum)
        guard mode == .sync, isEnabled, isOn(display), let builtinValue = builtin.map({ settings(for: $0).brightness }) else { return }
        let value = settings(for: display)
        setBrightness(SyncMath.map(builtin: builtinValue, minimum: value.minimum, maximum: value.maximum), for: display)
    }

    /// Brightness and extra dimming as one level (see `DisplaySettings.level`).
    func setLevel(_ value: Double, for display: Display) {
        let range = levelRange(for: display)
        update(display) { $0.setLevel(min(max(value, range.lowerBound), range.upperBound)) }
    }

    /// How low a display's level goes: below 0 is extra dimming, except where brightness is already done in
    /// software and going lower would only repeat it.
    func levelRange(for display: Display) -> ClosedRange<Double> {
        display.method == .software ? 0...1 : -DisplaySettings.maxDim...1
    }

    func update(_ display: Display, _ change: (inout DisplaySettings) -> Void) {
        freshDisplays.remove(display.key)
        var value = settings(for: display)
        change(&value)
        settings[display.key] = value
        if isOn(display) { engine?.apply(value, to: display) }
    }

    /// Presets set every display at once.
    func applyPreset(_ value: Double) {
        for display in displays where isOn(display) { setBrightness(value, for: display) }
    }

    func resetDisplay(_ display: Display) {
        settings[display.key] = DisplaySettings()
        if isOn(display) { engine?.apply(DisplaySettings(), to: display) }
    }

    /// The speaker volume shown for a DDC display: what it reported or was last set to, else halfway.
    func volume(for display: Display) -> Double {
        settings(for: display).volume ?? 0.5
    }

    func setVolume(_ value: Double, for display: Display) {
        settings[display.key, default: DisplaySettings()].volume = value
        engine?.setVolume(value, for: display)
    }

    func setSystemVolume(_ value: Double) {
        SystemVolume.set(value)
        systemVolume = SystemVolume.get()
    }

    /// The volume keys and other apps change it too.
    private func refreshSystemVolume() {
        let volume = SystemVolume.get()
        if volume != systemVolume { systemVolume = volume }
    }

    /// Hardware (DDC) or software dimming for a monitor that has DDC.
    func setControl(_ display: Display, _ choice: ControlChoice) {
        guard settings(for: display).control != choice else { return }
        settings[display.key, default: DisplaySettings()].control = choice
        switchedControl()
    }

    /// Re-picks each display's method and puts its brightness back with the new one.
    private func switchedControl() {
        engine?.resetGamma()
        reloadDisplays()
        guard isEnabled else { return }
        for shown in displays where isOn(shown) && shown.isActive { engine?.apply(settings(for: shown), to: shown) }
    }

    /// Controlled over DDC, but the monitor doesn't report its values back.
    func isDDCSilent(_ display: Display) -> Bool {
        display.method == .ddc && silentDDC.contains(display.key)
    }

    // MARK: - Power

    /// Displays showing a picture.
    var onCount: Int { displays.filter(isOn).count }

    /// The last display that's on can't be turned off.
    func canTurnOff(_ display: Display) -> Bool {
        isOn(display) && onCount > 1
    }

    /// Turns a display off (asking to keep it off, and turning it back on by itself if nobody answers), or on.
    func setPower(_ display: Display, on: Bool) {
        on ? turnOn(display) : turnOff(display)
    }

    private func turnOff(_ display: Display) {
        guard let engine, canTurnOff(display) else { return }
        // Saved before macOS is asked, so a crash right after still turns it back on at the next launch.
        offDisplays[display.key] = display
        powerOff[display.key] = .disabled
        engine.turnedOff.insert(display.key)
        if !engine.setActive(display, false) {
            offDisplays[display.key] = nil
            powerOff[display.key] = .blackout
            engine.turnedOff.remove(display.key)
            engine.setBlackout(display, true)
        }
        let blackout = powerOff[display.key] == .blackout
        reloadDisplays()
        // Ask on the next turn, once macOS has moved the windows off the display.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !PowerConfirmation.keepOff(name: self.displayName(display), blackout: blackout) { self.turnOn(display) }
        }
    }

    private func turnOn(_ display: Display) {
        guard let engine, let state = powerOff[display.key] else { return }
        switch state {
        case .disabled:
            // It stays listed as off until it's really showing a picture (see `reloadDisplays`), so a display
            // that doesn't come back can be tried again.
            turningOn.insert(display.key)
            engine.turnOn(ids: [offDisplays[display.key]?.id ?? display.id], keys: [display.key])
            // Some displays take a while to wake; if it's still dark after a few seconds, ask once more.
            let key = display.key
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.turningOn.contains(key) else { return }
                self.engine?.turnOn(ids: [self.offDisplays[key]?.id ?? display.id], keys: [key])
                self.reloadDisplays()
            }
        case .blackout:
            engine.setBlackout(display, false)
            powerOff[display.key] = nil
            engine.turnedOff.remove(display.key)
        }
        reloadDisplays()
    }

    /// Every display this app turned off comes back on (⌃⌥⌘B, Quit, Restore Defaults).
    func turnAllOn() {
        guard let engine else { return }
        for (key, state) in powerOff {
            switch state {
            case .disabled:
                turningOn.insert(key)
            case .blackout:
                if let display = displays.first(where: { $0.key == key }) { engine.setBlackout(display, false) }
                powerOff[key] = nil
                engine.turnedOff.remove(key)
            }
        }
        let keys = Set(powerOff.keys)
        if !keys.isEmpty { engine.turnOn(ids: keys.compactMap { offDisplays[$0]?.id }, keys: keys) }
        reloadDisplays()
    }

    private func reloadDisplays() {
        guard let engine else { return }
        engine.softwareOnly = Set(settings.filter { $0.value.control == .software }.keys)
        engine.refresh()
        var listed = engine.displays
        // A display asked back on is done once it's showing a picture: forget it and give it its brightness.
        for key in turningOn {
            guard let display = listed.first(where: { $0.key == key && $0.isActive }) else { continue }
            turningOn.remove(key)
            powerOff[key] = nil
            offDisplays[key] = nil
            engine.turnedOff.remove(key)
            if isEnabled { engine.apply(settings(for: display), to: display) }
        }
        // A turned-off display that dropped out of the connected list stays listed, as Off, so it can be turned on.
        for (key, display) in offDisplays where powerOff[key] == .disabled && !listed.contains(where: { $0.key == key }) {
            var off = display
            off.isActive = false
            listed.append(off)
        }
        displays = listed.sorted { ($0.isBuiltin ? 0 : 1, $0.name) < ($1.isBuiltin ? 0 : 1, $1.name) }
        // Blacked-out displays stay black (reconnecting resets their gamma). Turned-off ones are never forgotten
        // here: only turning them on clears them, so one can't end up off with no way back from the app.
        for (key, state) in powerOff where state == .blackout {
            if let display = displays.first(where: { $0.key == key }) { engine.setBlackout(display, true) }
        }
        for display in displays {
            if settings[display.key] == nil {
                // A new display starts from what it shows now: macOS's value, the monitor's DDC reading
                // (arrives a moment later), or undimmed.
                var initial = DisplaySettings()
                initial.brightness = engine.currentBrightness(of: display) ?? 1
                settings[display.key] = initial
                freshDisplays.insert(display.key)
            } else if isEnabled, display.method != .native, display.isActive, isOn(display), !freshDisplays.contains(display.key) {
                // Saved displays get their brightness back; natively controlled ones keep macOS's.
                engine.apply(settings(for: display), to: display)
            }
        }
        if let key = openDisplayKey, !displays.contains(where: { $0.key == key }) { openDisplayKey = nil }
        // A display that just connected joins Sync right away, not at the next built-in brightness change.
        lastBuiltin = nil
        followBuiltin()
    }

    /// Tracks the built-in display's brightness (it changes with the keys and ambient light); in Sync mode the
    /// external displays follow it.
    private func followBuiltin() {
        guard let engine, let builtin, let builtinValue = engine.builtinBrightness(),
              lastBuiltin.map({ abs($0 - builtinValue) > 0.004 }) ?? true else { return }
        lastBuiltin = builtinValue
        if builtinValue > 0, settings(for: builtin).extraDim > 0 {
            // The brightness keys took it back above 0%: the extra dimming below 0% goes too.
            update(builtin) { $0.setLevel(builtinValue) }
        } else {
            settings[builtin.key]?.brightness = builtinValue
        }
        guard mode == .sync, isEnabled else { return }
        for display in externals where isOn(display) {
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
              isEnabled, display.method != .native else { return false }
        let value = SyncMath.stepped(settings(for: display).level, up: up, lowest: levelRange(for: display).lowerBound)
        setLevel(value, for: display)
        BrightnessOSD.shared.show(max(value, 0), on: display.id)
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
        turnAllOn()
        engine?.resetGamma()
        settings = [:]
        mode = .manual
        reloadDisplays()
    }

    /// Leaves the displays as macOS would have them.
    func prepareToQuit() {
        turnAllOn()
        engine?.resetGamma()
    }

    // MARK: - Snapshot / self-test support

    func simulate(displays: [Display], settings: [String: DisplaySettings], powerOff: [String: PowerOff] = [:],
                  silentDDC: Set<String> = [], systemVolume: Double? = nil) {
        self.systemVolume = systemVolume
        self.displays = displays
        self.silentDDC = silentDDC
        self.settings = settings
        self.powerOff = powerOff
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
