import AppKit
import ApplicationServices
import Carbon.HIToolbox
import LongoKitUI
import ServiceManagement

enum MainTab: CaseIterable {
    case general, keyboards, hyper, about

    var title: String {
        switch self {
        case .general: return L("General")
        case .keyboards: return L("Keyboards")
        case .hyper: return L("Hyper")
        case .about: return L("About")
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var keyboards: [KeyboardDevice] = []
    /// "All keyboards": used by every keyboard without its own settings. Only confirmed changes are saved.
    @Published private(set) var shared: KeyboardProfile
    /// Keyboards with their own settings, by id.
    @Published private(set) var profiles: [String: KeyboardProfile]
    @Published var hyper: [HyperBinding] {
        didSet {
            save(hyper, forKey: Keys.hyper)
            applyBindings()
        }
    }
    /// Paused (⌃⌥⌘K), every keyboard is back to normal.
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            HyperTap.shared.isEnabled = isEnabled
            applyMappings()
        }
    }
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
    /// A password field has Secure Input on: macOS hides keystrokes from the Hyper key until it's left.
    @Published private(set) var secureInput = false

    @Published var tab: MainTab = .general {
        // Coming back to Keyboards from another tab starts at the list.
        didSet { if tab != oldValue { openKeyboard = nil } }
    }
    /// The keyboard whose page is open on the Keyboards tab; `allKeyboards` is the shared settings.
    @Published var openKeyboard: String?
    static let allKeyboards = "all"

    private let defaults: UserDefaults
    private let live: Bool
    private let monitor = KeyboardMonitor()
    private var pauseKey: GlobalHotKey?
    private var timer: Timer?
    /// A keep-or-revert question is open; further changes wait for it.
    private var confirming = false

    private enum Keys {
        static let shared = "sharedProfile"
        static let profiles = "keyboardProfiles"
        static let hyper = "hyperBindings"
        static let enabled = "enabled"
        static let language = "language"
        static let appearance = "appearance"
        static let menuBarIcon = "showMenuBarIcon"
        /// Set while key tables this app wrote may be on keyboards, so a crash is cleaned up at the next launch.
        static let applied = "mappingsApplied"
    }

    /// `live: false` for snapshots and the self-test: no keyboards touched, no tap, no hot key.
    init(live: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.live = live
        func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
            defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
        }
        shared = load(KeyboardProfile.self, Keys.shared) ?? KeyboardProfile()
        profiles = load([String: KeyboardProfile].self, Keys.profiles) ?? [:]
        hyper = load([HyperBinding].self, Keys.hyper) ?? HyperBinding.defaults
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .system
        let menuBarIcon = defaults.object(forKey: Keys.menuBarIcon) as? Bool ?? true
        showMenuBarIcon = menuBarIcon
        MainWindowRef.keepsDockIconWhenHidden = !menuBarIcon
        Localizer.language = language
        applyAppearance()
        HyperTap.shared.isEnabled = isEnabled
        applyBindings()
        guard live else { return }

        // Tables from a run that crashed first come off; then the confirmed ones go back on.
        if defaults.bool(forKey: Keys.applied) { KeyMapper.clearAll() }
        monitor.onChange = { [weak self] list in
            guard let self else { return }
            self.keyboards = list
            if let id = self.openKeyboard, id != Self.allKeyboards, !list.contains(where: { $0.id == id }) { self.openKeyboard = nil }
            // A keyboard that just connected has no table yet; its services can lag behind the device.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.applyMappings() }
        }
        monitor.start()

        pauseKey = GlobalHotKey(controlOptionCommand: kVK_ANSI_K, id: 3) { [weak self] in
            MainActor.assumeIsolated { self?.isEnabled.toggle() }
        }
        startTapIfPossible()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    // MARK: - Profiles

    func profile(for id: String?) -> KeyboardProfile {
        guard let id, id != Self.allKeyboards else { return shared }
        return profiles[id] ?? shared
    }

    func hasOwnSettings(_ id: String) -> Bool { profiles[id] != nil }

    func keyboard(_ id: String) -> KeyboardDevice? { keyboards.first { $0.id == id } }

    func displayName(_ keyboard: KeyboardDevice) -> String {
        keyboard.isBuiltIn ? L("Built-in Keyboard") : keyboard.name
    }

    /// Own settings start as a copy of the shared ones; turning them off goes back to the shared ones.
    func setOwnSettings(_ id: String, _ on: Bool) {
        guard on != hasOwnSettings(id) else { return }
        commit { profiles, _ in profiles[id] = on ? self.shared : nil }
    }

    /// Changes a keyboard's settings (or the shared ones, for nil / `allKeyboards`).
    func change(_ id: String?, _ edit: (inout KeyboardProfile) -> Void) {
        var value = profile(for: id)
        edit(&value)
        commit { profiles, shared in
            if let id, id != Self.allKeyboards { profiles[id] = value } else { shared = value }
        }
    }

    /// Every change to what keys do goes through here: it's checked, applied, then kept only if confirmed.
    private func commit(_ edit: (inout [String: KeyboardProfile], inout KeyboardProfile) -> Void) {
        guard !confirming else { return }
        var newProfiles = profiles, newShared = shared
        edit(&newProfiles, &newShared)
        guard newProfiles != profiles || newShared != shared else { return }

        // A keyboard must always be able to type the essentials (and ⌃⌥⌘K).
        let physical = KeyboardLayout.physicalKeys
        for profile in [newShared] + Array(newProfiles.values) {
            if let missing = profile.problem(physicalKeys: physical) {
                Self.refuse(missing)
                return
            }
        }

        let before = (profiles, shared, tables())
        profiles = newProfiles
        shared = newShared
        applyMappings()
        // Nothing a keyboard sends changed (say, edits to a disconnected keyboard): keep without asking.
        guard live, tables() != before.2 else { return persist() }

        confirming = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let keep = KeepChanges.ask()
            self.confirming = false
            if keep {
                self.persist()
            } else {
                self.profiles = before.0
                self.shared = before.1
                self.applyMappings()
            }
        }
    }

    private func persist() {
        save(shared, forKey: Keys.shared)
        save(profiles, forKey: Keys.profiles)
    }

    private static func refuse(_ missing: String) {
        let alert = NSAlert()
        alert.messageText = L("That would leave a keyboard without %@", missing)
        alert.informativeText = L("Esc, Return, ⌘, ⌃, ⌥ and K must always come from some key, so the keyboard stays usable and ⌃⌥⌘K can pause LongoKeys.")
        alert.addButton(withTitle: L("OK"))
        alert.runModal()
    }

    // MARK: - Applying

    /// What each connected keyboard should have now.
    private func tables() -> [String: [Key: Key]] {
        var result: [String: [Key: Key]] = [:]
        for keyboard in keyboards {
            result[keyboard.id] = isEnabled ? profile(for: keyboard.id).mapping(hyperReady: HyperTap.shared.isRunning) : [:]
        }
        return result
    }

    func applyMappings() {
        guard live else { return }
        let tables = tables()
        KeyMapper.apply(keyboards.map { ($0, tables[$0.id] ?? [:]) })
        defaults.set(tables.values.contains { !$0.isEmpty }, forKey: Keys.applied)
    }

    private func applyBindings() {
        var bindings: [Int: HyperAction] = [:]
        for binding in hyper { if let code = binding.trigger.keyCode { bindings[code] = binding.action } }
        HyperTap.shared.bindings = bindings
    }

    /// Every keyboard as it was, when quitting.
    func prepareToQuit() {
        guard live else { return }
        KeyMapper.apply(keyboards.map { ($0, [:]) })
        defaults.set(false, forKey: Keys.applied)
    }

    // MARK: - Hyper layer

    func binding(for key: Key) -> HyperBinding? { hyper.first { $0.trigger == key } }

    func setBinding(_ key: Key, _ action: HyperAction?) {
        hyper.removeAll { $0.trigger == key }
        if let action { hyper.append(HyperBinding(trigger: key, action: action)) }
        hyper.sort { $0.trigger.usage < $1.trigger.usage }
    }

    var usesHyper: Bool {
        shared.caps == .hyper || profiles.values.contains { $0.caps == .hyper }
    }

    // MARK: - Permissions & startup

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func tick() {
        let trusted = AXIsProcessTrusted()
        if trusted != hasAccessibility {
            hasAccessibility = trusted
            startTapIfPossible()
        }
        let secure = IsSecureEventInputEnabled()
        if secure != secureInput { secureInput = secure }
    }

    /// The Hyper key needs the tap; Caps Lock only becomes F18 once it runs (see `KeyboardProfile.mapping`).
    private func startTapIfPossible() {
        guard hasAccessibility, !HyperTap.shared.isRunning else { return }
        if HyperTap.shared.start() {
            applyMappings()
            objectWillChange.send()
        }
    }

    func setStartAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Start at login failed: \(error.localizedDescription)")
        }
        startAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Every keyboard back to normal and the Hyper layer to its defaults, confirmed like any other change.
    func restoreDefaults() {
        commit { profiles, shared in
            profiles = [:]
            shared = KeyboardProfile()
        }
        hyper = HyperBinding.defaults
    }

    // MARK: - Snapshot / self-test support

    func simulate(keyboards: [KeyboardDevice], shared: KeyboardProfile, profiles: [String: KeyboardProfile]) {
        self.keyboards = keyboards
        self.shared = shared
        self.profiles = profiles
    }

    // MARK: - Helpers

    private var appearanceObservation: NSKeyValueObservation?

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

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
