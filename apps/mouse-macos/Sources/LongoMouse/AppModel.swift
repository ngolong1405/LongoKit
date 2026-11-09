import AppKit
import Carbon.HIToolbox
import Combine
import IOKit.hid
import LongoKitUI
import ServiceManagement

/// Everything the UI shows: bindings, settings and permission state. Mirrors what the engine needs into it.
final class AppModel: ObservableObject {
    enum Recording: Equatable {
        case key(UUID)
    }

    /// The global layout, used by every mouse without a separate profile.
    @Published var bindings: [MouseBinding] {
        didSet {
            applyEngineBindings()
            save(bindings, forKey: Keys.bindings)
        }
    }

    /// Every mouse ever seen, keyed by `MouseDevice.id`.
    @Published var profiles: [String: DeviceProfile] {
        didSet {
            applyEngineBindings()
            applyEngineScroll()
            save(profiles, forKey: Keys.profiles)
        }
    }

    /// Use the profile of whichever mouse last sent input.
    @Published var autoSwitchProfiles: Bool {
        didSet {
            defaults.set(autoSwitchProfiles, forKey: Keys.autoSwitch)
            applyEngineBindings()
            applyEngineScroll()
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

    @Published var tab: MainTab = .general {
        didSet {
            // With a single mouse there's nothing to pick, so the first visit goes straight to its settings.
            if tab == .devices, !didAutoOpenDevice, !showingDeviceDetail, connectedDevices.count == 1,
               let id = connectedDevices.first?.id {
                didAutoOpenDevice = true
                open(id)
            }
        }
    }
    /// The mouse whose settings page is open; nil is the shared settings for all mice.
    @Published var editingDeviceID: String?
    /// The Devices tab shows a mouse's settings page instead of the list. Kept while switching tabs,
    /// so coming back lands on the mouse you were setting up.
    @Published var showingDeviceDetail = false
    @Published var deviceSection: DeviceSection = .buttons
    private var didAutoOpenDevice = false
    @Published private(set) var connectedDevices: [MouseDevice] = []
    @Published private(set) var activeDeviceID: String? {
        didSet {
            applyEngineBindings()
            applyEngineScroll()
        }
    }

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            syncEngine()
        }
    }

    @Published var scroll: ScrollSettings {
        didSet {
            applyEngineScroll()
            save(scroll, forKey: Keys.scroll)
        }
    }

    @Published var showMenuBarIcon: Bool {
        didSet {
            defaults.set(showMenuBarIcon, forKey: Keys.menuBarIcon)
            // Without the menu bar icon, the Dock icon is the only way back to a hidden window.
            MainWindowRef.keepsDockIconWhenHidden = !showMenuBarIcon
        }
    }

    @Published var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: Keys.autoUpdates) }
    }

    @Published private(set) var startAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var hasAccessibility = MouseEngine.hasAccessibility
    @Published private(set) var hasInputMonitoring = AppModel.checkInputMonitoring()
    @Published private(set) var recording: Recording?
    @Published private(set) var isCapturing = false
    /// "Button 4 · Click" for the last gesture recorded in the current listening session.
    @Published private(set) var lastCapture: String?
    /// True while an action picker popover is open; the window dims behind it.
    @Published var isPickingAction = false
    /// The row that was just recorded, briefly highlighted in the Buttons list.
    @Published private(set) var highlighted: UUID?
    /// Set once an update feed exists; the About tab then shows the "new version" card.
    @Published private(set) var availableUpdate: AppUpdate?

    var isRunning: Bool { isEnabled && hasAccessibility && (runningOverride ?? MouseEngine.shared.isRunning) }
    var allPermissionsGranted: Bool { hasAccessibility && hasInputMonitoring }

    var menuBarState: MouseGlyph.State {
        isCapturing ? .listening : isRunning ? .running : .idle
    }

    private let defaults: UserDefaults
    private var keyMonitor: Any?
    private var captureMonitor: Any?
    /// When a click last stopped listening; that same click must not start it again on mouse-up.
    private var lastClickStop = Date.distantPast
    private var runningOverride: Bool?
    private var permissionTimer: Timer?
    private var pauseKey: GlobalHotKey?
    /// Input Monitoring granted after launch only takes effect in a new process.
    private let launchedWithInputMonitoring = AppModel.checkInputMonitoring()
    /// Shown on the General tab during the short pause before restarting.
    @Published private(set) var isRelaunching = false
    private var appearanceObservation: NSKeyValueObservation?
    private let deviceMonitor = DeviceMonitor()

    private enum Keys {
        static let bindings = "bindings"
        static let enabled = "enabled"
        static let scroll = "scroll"
        static let menuBarIcon = "showMenuBarIcon"
        static let autoUpdates = "autoCheckUpdates"
        static let profiles = "deviceProfiles"
        static let autoSwitch = "autoSwitchProfiles"
        static let language = "language"
        static let appearance = "appearance"
    }

    init(startsEngine: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bindings = Self.load([MouseBinding].self, from: defaults, forKey: Keys.bindings) ?? Self.defaultBindings()
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        scroll = Self.load(ScrollSettings.self, from: defaults, forKey: Keys.scroll) ?? ScrollSettings()
        let menuBarIcon = defaults.object(forKey: Keys.menuBarIcon) as? Bool ?? true
        showMenuBarIcon = menuBarIcon
        MainWindowRef.keepsDockIconWhenHidden = !menuBarIcon
        autoCheckUpdates = defaults.object(forKey: Keys.autoUpdates) as? Bool ?? true
        profiles = Self.load([String: DeviceProfile].self, from: defaults, forKey: Keys.profiles) ?? [:]
        autoSwitchProfiles = defaults.object(forKey: Keys.autoSwitch) as? Bool ?? true
        language = (defaults.string(forKey: Keys.language)).flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
        appearance = (defaults.string(forKey: Keys.appearance)).flatMap(AppAppearance.init(rawValue:)) ?? .system
        Localizer.language = language
        applyAppearance()

        applyEngineBindings()
        applyEngineScroll()
        syncEngine()
        guard startsEngine else { return }

        // The way out if a mapping gets in the way: every button and the wheel back to normal, from any app.
        pauseKey = GlobalHotKey(controlOptionCommand: kVK_ANSI_M, id: 2) { [weak self] in
            guard let self, self.hasAccessibility else { return }
            self.isEnabled.toggle()
        }

        refreshPermissions()
        // Permissions change in System Settings without telling us, so re-check on focus and on a timer.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.refreshPermissions()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.setCapturing(false)
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }

        deviceMonitor.onChange = { [weak self] in self?.devicesChanged($0) }
        deviceMonitor.onActivity = { [weak self] in self?.activeDeviceID = $0 }
        deviceMonitor.start()
    }

    // MARK: - Engine & permissions

    func refreshPermissions() {
        let accessibility = MouseEngine.hasAccessibility
        let inputMonitoring = Self.checkInputMonitoring()
        let gained = (accessibility && !hasAccessibility) || (inputMonitoring && !hasInputMonitoring)
        if accessibility != hasAccessibility {
            // Without access the switch reads off; once access arrives, turn remapping on.
            isEnabled = accessibility
            hasAccessibility = accessibility
        } else if !accessibility && isEnabled {
            isEnabled = false
        }
        if inputMonitoring != hasInputMonitoring { hasInputMonitoring = inputMonitoring }
        var tapFailed = false
        if accessibility && !MouseEngine.shared.isRunning {
            tapFailed = !MouseEngine.shared.start()
            objectWillChange.send()
        }
        syncEngine()
        if gained { permissionGranted(tapFailed: tapFailed) }
    }

    /// A permission just came through in System Settings: come back to the front, and once everything is granted,
    /// restart if this process can't pick the change up by itself.
    private func permissionGranted(tapFailed: Bool) {
        MainWindowRef.show()
        guard allPermissionsGranted, !isRelaunching,
              tapFailed || !launchedWithInputMonitoring else { return }
        isRelaunching = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { Self.relaunch() }
    }

    /// Starts a fresh copy of the app once this one has quit, then quits.
    private static func relaunch() {
        let bundle = Bundle.main.bundlePath
        guard bundle.hasSuffix(".app") else { return } // `swift run` has no bundle to reopen
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$0\"", bundle]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            NSLog("Relaunch failed: \(error.localizedDescription)")
        }
    }

    func toggleEnabled() {
        if hasAccessibility {
            isEnabled.toggle()
        } else {
            isEnabled = true
            requestAccessibility()
        }
    }

    func requestAccessibility() {
        MouseEngine.requestAccessibility()
        openAccessibilitySettings()
    }

    func requestInputMonitoring() {
        if !IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
            openPrivacyPane("Privacy_ListenEvent")
        }
        refreshPermissions()
    }

    /// The primary "Grant Permission" button walks through whatever is still missing.
    func grantNextPermission() {
        hasAccessibility ? requestInputMonitoring() : requestAccessibility()
    }

    func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openPrivacyPane("Privacy_ListenEvent")
    }

    func setStartAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Start at login failed: \(error.localizedDescription)")
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        startAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Snapshot rendering only: pretend permissions and the event tap are in a given state.
    func simulate(granted: Bool) {
        hasAccessibility = granted
        hasInputMonitoring = granted
        runningOverride = granted
    }

    /// NSApp may not exist yet during launch, so apply on the next turn of the run loop.
    private func applyAppearance() {
        let appearance = appearance.nsAppearance
        DispatchQueue.main.async { [weak self] in
            guard let app = NSApp else { return }
            app.appearance = appearance
            Self.updateDockIcon()
            // "System" follows macOS switching light/dark on its own, so keep the Dock icon in step.
            if self?.appearanceObservation == nil {
                self?.appearanceObservation = app.observe(\.effectiveAppearance) { _, _ in
                    DispatchQueue.main.async { Self.updateDockIcon() }
                }
            }
        }
    }

    /// Dock icon matching the current appearance: white tile in light mode, dark tile in dark mode.
    private static func updateDockIcon() {
        guard let app = NSApp else { return }
        let dark = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        app.applicationIconImage = Brand.logo(dark: dark)
    }

    private func syncEngine() {
        MouseEngine.shared.isEnabled = isEnabled && hasAccessibility
    }

    private func openPrivacyPane(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }

    private static func checkInputMonitoring() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    // MARK: - Buttons

    struct BindingGroup: Identifiable {
        let trigger: Trigger
        let rows: [MouseBinding]
        var id: Trigger { trigger }
    }

    var groups: [BindingGroup] {
        let order = ClickType.allCases
        return Dictionary(grouping: editing, by: \.trigger)
            .map { trigger, rows in
                BindingGroup(trigger: trigger, rows: rows.sorted {
                    order.firstIndex(of: $0.clickType)! < order.firstIndex(of: $1.clickType)!
                })
            }
            .sorted { ($0.trigger.button, $0.trigger.modifiers.rawValue) < ($1.trigger.button, $1.trigger.modifiers.rawValue) }
    }

    /// Clicking the capture field starts listening: each extra-button gesture becomes a row
    /// until Esc, a click anywhere, or the app losing focus stops it.
    func setCapturing(_ on: Bool) {
        guard on != isCapturing else { return }
        // A click on a Listen/Stop control first stops listening via the click monitor below; its
        // action then fires on mouse-up and would immediately restart it. Swallow that restart.
        if on && Date().timeIntervalSince(lastClickStop) < 0.5 { return }
        isCapturing = on
        lastCapture = nil
        MouseEngine.shared.captureHandler = on ? { [weak self] trigger, type in self?.captured(trigger, type) } : nil
        if let captureMonitor {
            NSEvent.removeMonitor(captureMonitor)
            self.captureMonitor = nil
        }
        guard on else { return }
        // Install after the click that started listening, so that click doesn't immediately stop it.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCapturing, self.captureMonitor == nil else { return }
            self.captureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
                let isEscape = event.type == .keyDown && event.keyCode == 53
                if event.type != .keyDown { self?.lastClickStop = Date() }
                if isEscape || event.type != .keyDown { self?.setCapturing(false) }
                return isEscape ? nil : event
            }
        }
    }

    private func captured(_ trigger: Trigger, _ type: ClickType) {
        lastCapture = "\(trigger.title) · \(type.title)"
        let id: UUID
        if let existing = editing.first(where: { $0.trigger == trigger && $0.clickType == type }) {
            // Already configured: stop listening and point at the tile instead of adding a duplicate.
            id = existing.id
            setCapturing(false)
        } else {
            let binding = MouseBinding(trigger: trigger, clickType: type, action: Self.defaultAction(trigger, type))
            editing.append(binding)
            id = binding.id
        }
        highlighted = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.highlighted == id { self?.highlighted = nil }
        }
    }

    func remove(_ id: UUID) {
        if recording == .key(id) { cancelRecording() }
        editing.removeAll { $0.id == id }
    }

    /// Sets a gesture's action, creating the gesture first if it was only a draft in the picker.
    func assign(_ action: ActionKind, to id: UUID, trigger: Trigger, clickType: ClickType) {
        upsert(id, trigger, clickType) { $0.action = action }
    }

    func assign(_ key: MediaKey, to id: UUID, trigger: Trigger, clickType: ClickType) {
        upsert(id, trigger, clickType) {
            $0.action = .mediaKey
            $0.mediaKey = key
        }
    }

    private func upsert(_ id: UUID, _ trigger: Trigger, _ clickType: ClickType, _ change: (inout MouseBinding) -> Void) {
        if !editing.contains(where: { $0.id == id }) {
            editing.append(MouseBinding(id: id, trigger: trigger, clickType: clickType))
        }
        update(id, change)
    }

    func removeGroup(_ trigger: Trigger) {
        editing.removeAll { $0.trigger == trigger }
    }

    func setAction(_ id: UUID, _ action: ActionKind) {
        update(id) { $0.action = action }
    }

    func setMediaKey(_ id: UUID, _ key: MediaKey) {
        update(id) {
            $0.action = .mediaKey
            $0.mediaKey = key
        }
    }

    /// Records a key combination for a gesture. With `creating`, a draft gesture is added once a key is pressed.
    func recordShortcut(for id: UUID, creating draft: (Trigger, ClickType)? = nil) {
        cancelRecording()
        recording = .key(id)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let modifiers = Modifiers(event.modifierFlags)
            if event.keyCode == 53 && modifiers.isEmpty {
                self.cancelRecording()
                return nil
            }
            let shortcut = KeyShortcut(keyCode: event.keyCode, modifiers: modifiers, keyName: Self.keyName(event))
            if let draft, !self.editing.contains(where: { $0.id == id }) {
                self.editing.append(MouseBinding(id: id, trigger: draft.0, clickType: draft.1))
            }
            self.update(id) {
                $0.action = .shortcut
                $0.shortcut = shortcut
            }
            self.cancelRecording()
            return nil
        }
    }

    func cancelRecording() {
        recording = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func update(_ id: UUID, _ change: (inout MouseBinding) -> Void) {
        guard let index = editing.firstIndex(where: { $0.id == id }) else { return }
        change(&editing[index])
    }

    static func defaultBindings() -> [MouseBinding] {
        [
            MouseBinding(trigger: Trigger(button: 3, modifiers: []), action: .back),
            MouseBinding(trigger: Trigger(button: 4, modifiers: []), action: .forward),
        ]
    }

    private static func defaultAction(_ trigger: Trigger, _ type: ClickType) -> ActionKind {
        switch type {
        case .click:
            switch trigger.button {
            case 3: return .back
            case 4: return .forward
            default: return .missionControl
            }
        case .doubleClick: return .showDesktop
        case .hold: return .appExpose
        case .drag: return .dragSpaces
        case .scroll: return .scrollZoom
        }
    }

    private static func keyName(_ event: NSEvent) -> String {
        if let name = specialKeys[event.keyCode] { return name }
        return event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
    }

    private static let specialKeys: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    // MARK: - Devices

    /// What the Buttons tab currently edits: a mouse's separate profile, or the global layout.
    var editing: [MouseBinding] {
        get {
            if let id = editingDeviceID, let profile = profiles[id], profile.independent { return profile.bindings }
            return bindings
        }
        set {
            if let id = editingDeviceID, profiles[id]?.independent == true {
                profiles[id]?.bindings = newValue
            } else {
                bindings = newValue
            }
        }
    }

    /// True when the Buttons tab targets a mouse that has its own profile.
    var editingSeparateProfile: Bool {
        editingDeviceID.flatMap { profiles[$0]?.independent } ?? false
    }

    var activeDevice: MouseDevice? {
        connectedDevices.first { $0.id == activeDeviceID } ?? connectedDevices.first
    }

    var offlineDeviceIDs: [String] {
        let online = Set(connectedDevices.map(\.id))
        return profiles.filter { !online.contains($0.key) }
            .sorted { $0.value.lastSeen > $1.value.lastSeen }
            .map(\.key)
    }

    func displayName(_ id: String?) -> String {
        guard let id else { return L("All Devices") }
        return profiles[id]?.displayName ?? connectedDevices.first { $0.id == id }?.product ?? "Mouse"
    }

    func isConnected(_ id: String) -> Bool {
        connectedDevices.contains { $0.id == id }
    }

    func refreshDevices() {
        deviceMonitor.refresh()
    }

    func openBluetoothSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
    }

    /// Opens a mouse's settings page (nil: the shared settings).
    func open(_ id: String?, section: DeviceSection? = nil) {
        editingDeviceID = id
        if let section { deviceSection = section }
        showingDeviceDetail = true
    }

    func configure(_ id: String?) {
        open(id, section: .buttons)
        tab = .devices
    }

    /// Turning a separate profile on starts it from a copy of the global layout.
    func setIndependent(_ id: String, _ on: Bool) {
        guard var profile = profiles[id] else { return }
        if on && profile.bindings.isEmpty { profile.bindings = Self.copies(of: bindings) }
        profile.independent = on
        profiles[id] = profile
    }

    func setNickname(_ id: String, _ name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespaces) ?? ""
        profiles[id]?.customName = trimmed.isEmpty ? nil : trimmed
    }

    func forget(_ id: String) {
        if editingDeviceID == id { editingDeviceID = nil }
        profiles.removeValue(forKey: id)
    }

    private func devicesChanged(_ devices: [MouseDevice]) {
        connectedDevices = devices
        var updated = profiles
        for device in devices {
            var profile = updated[device.id] ?? DeviceProfile(product: device.product, manufacturer: device.manufacturer,
                                                              connection: device.connection, hardwareID: device.hardwareID)
            profile.product = device.product
            profile.manufacturer = device.manufacturer
            profile.connection = device.connection
            profile.hardwareID = device.hardwareID
            profile.lastSeen = Date()
            updated[device.id] = profile
        }
        if updated != profiles { profiles = updated }
        if let active = activeDeviceID, !isConnected(active) { activeDeviceID = nil }
    }

    /// The mouse whose own layout the engine is using right now; nil when the shared layout applies.
    var activeProfileDeviceID: String? {
        guard autoSwitchProfiles,
              let id = activeDeviceID ?? (connectedDevices.count == 1 ? connectedDevices.first?.id : nil),
              profiles[id]?.independent == true else { return nil }
        return id
    }

    /// The layout the engine should use right now.
    private var effectiveBindings: [MouseBinding] {
        activeProfileDeviceID.flatMap { profiles[$0]?.bindings } ?? bindings
    }

    private func applyEngineBindings() {
        MouseEngine.shared.update(effectiveBindings)
    }

    // MARK: - Per-mouse scrolling

    /// What the Scrolling tab edits: the selected mouse's own settings, or the shared ones.
    var editingScroll: ScrollSettings {
        get { editingDeviceID.flatMap { profiles[$0]?.scroll } ?? scroll }
        set {
            if let id = editingDeviceID, profiles[id]?.scroll != nil {
                profiles[id]?.scroll = newValue
            } else {
                scroll = newValue
            }
        }
    }

    /// True when the Scrolling tab targets a mouse with its own scroll settings.
    var editingOwnScroll: Bool {
        editingDeviceID.flatMap { profiles[$0]?.scroll } != nil
    }

    /// Turning own scrolling on starts from a copy of the shared settings.
    /// The scrolling a mouse uses: its own, or the shared settings (`nil` is "All mice").
    func scrollSettings(for id: String?) -> ScrollSettings {
        id.flatMap { profiles[$0]?.scroll } ?? scroll
    }

    /// Changes a mouse's scrolling: its own if it has them, otherwise the shared settings.
    func updateScroll(for id: String?, _ change: (inout ScrollSettings) -> Void) {
        if let id, var own = profiles[id]?.scroll {
            change(&own)
            profiles[id]?.scroll = own
        } else {
            change(&scroll)
        }
    }

    func setOwnScroll(_ id: String, _ on: Bool) {
        guard profiles[id] != nil else { return }
        profiles[id]?.scroll = on ? (profiles[id]?.scroll ?? scroll) : nil
    }

    /// The mouse whose own scroll settings the engine is using right now; nil when the shared ones apply.
    var activeScrollDeviceID: String? {
        guard autoSwitchProfiles,
              let id = activeDeviceID ?? (connectedDevices.count == 1 ? connectedDevices.first?.id : nil),
              profiles[id]?.scroll != nil else { return nil }
        return id
    }

    /// The settings in effect for the mouse in use; the menu bar popover edits these.
    var inUseScroll: ScrollSettings {
        get { activeScrollDeviceID.flatMap { profiles[$0]?.scroll } ?? scroll }
        set {
            if let id = activeScrollDeviceID {
                profiles[id]?.scroll = newValue
            } else {
                scroll = newValue
            }
        }
    }

    private func applyEngineScroll() {
        MouseEngine.shared.scroll = inUseScroll
    }

    private static func copies(of bindings: [MouseBinding]) -> [MouseBinding] {
        bindings.map {
            var copy = $0
            copy.id = UUID()
            return copy
        }
    }

    /// Snapshot rendering only: pretend these mice are attached.
    func simulate(devices: [MouseDevice], active: String?) {
        devicesChanged(devices)
        activeDeviceID = active
    }

    // MARK: - Window footer

    func restoreDefaults(for tab: MainTab) {
        let detail = tab == .devices && showingDeviceDetail
        let scope = detail ? deviceSection.title : tab.title
        let alert = NSAlert()
        alert.messageText = L("Restore %@ defaults?", scope)
        alert.informativeText = detail
            ? L("This resets the %@ settings of %@. It can't be undone.", scope, displayName(editingDeviceID))
            : L("This resets the settings on the %@ tab. It can't be undone.", scope)
        alert.addButton(withTitle: L("Restore Defaults"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        switch tab {
        case .general:
            isEnabled = true
            showMenuBarIcon = true
            autoCheckUpdates = true
        case .devices where detail && deviceSection == .buttons:
            editing = Self.defaultBindings()
        case .devices where detail:
            editingScroll = ScrollSettings()
        case .devices:
            autoSwitchProfiles = true
        case .about:
            break
        }
    }

    func copyDiagnostics() {
        var lines = [
            "\(AppInfo.name) \(AppInfo.version) (\(AppInfo.build))",
            SystemInfo.summary,
            "Accessibility: \(hasAccessibility ? "granted" : "missing")",
            "Input Monitoring: \(hasInputMonitoring ? "granted" : "missing")",
            "Remapping: \(isRunning ? "running" : "paused")",
            "Bindings:",
        ]
        lines += bindings.map { "  \($0.trigger.title) · \($0.clickType.title) → \($0.actionTitle)" }
        lines.append("Devices:")
        lines += connectedDevices.map {
            "  \($0.product) [\($0.hardwareID)] \($0.connection)\(profiles[$0.id]?.independent == true ? " · separate profile" : "")"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    func checkForUpdates() {
        let alert = NSAlert()
        alert.messageText = L("Update checks aren't set up yet")
        alert.informativeText = L("This build has no update feed. Install new versions from the latest LongoMouse.dmg.")
        alert.runModal()
    }

    func dismissUpdate() {
        availableUpdate = nil
    }

    // MARK: - Persistence

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

struct AppUpdate: Equatable {
    var version: String
    var highlights: [String]
    var notesURL: URL?
}
