import AppKit
import Combine
import LongoKitUI
import ServiceManagement
import SwiftUI

/// LongoKit's state: which modules run, the settings they all share, and the page that's open.
@MainActor
final class Suite: ObservableObject {
    enum Page: Hashable {
        case general, module(String), about
    }

    /// Where a module stands. On or off is one switch, wherever it shows: the module's own, the General page's, the
    /// menu bar's. Off stops it at once, and from the next launch it isn't even loaded.
    enum Status: Equatable {
        case off
        /// On, but its own app is running, so it waits for that to quit.
        case elsewhere
        case running
        /// On, but held back, like by a missing permission.
        case attention
    }

    @Published var page: Page = .general
    /// The module the menu bar popover shows.
    @Published var menuModule: String?
    @Published private(set) var hosts: [String: any HostedModule] = [:]
    @Published private(set) var statuses: [String: Status] = [:]
    /// What the menu bar shows instead of LongoKit's icon, like a recording's timer.
    @Published private(set) var menuBarImage: NSImage?
    @Published private(set) var enabled: Set<String> {
        didSet { defaults.set(enabled.sorted(), forKey: Keys.modules) }
    }

    @Published var language: AppLanguage {
        didSet {
            Localizer.language = language
            for host in hosts.values { host.language = language }
            defaults.set(language.rawValue, forKey: Keys.language)
        }
    }
    @Published var appearance: AppAppearance {
        didSet {
            applyAppearance()
            for host in hosts.values { host.appearance = appearance }
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
        }
    }
    @Published var showMenuBarIcon: Bool {
        didSet {
            defaults.set(showMenuBarIcon, forKey: Keys.menuBarIcon)
            MainWindowRef.keepsDockIconWhenHidden = !showMenuBarIcon
        }
    }
    @Published private(set) var startAtLogin = SMAppService.mainApp.status == .enabled

    /// Off for self-tests and snapshots: modules then touch nothing on the Mac.
    let live: Bool
    private let defaults: UserDefaults
    /// The defaults domain each module keeps its settings in: its own app's, so the two share one set of settings
    /// (they never run at once, so each starts from what the other last saved).
    private let storeName: @MainActor (String) -> String
    /// Whether a module's own app is running.
    private let runsElsewhere: (ModuleInfo) -> Bool
    private var subscriptions: [String: AnyCancellable] = [:]
    private var observers: [NSObjectProtocol] = []

    private enum Keys {
        static let modules = "modules"
        static let language = "language"
        static let appearance = "appearance"
        static let menuBarIcon = "showMenuBarIcon"
        static func shared(_ id: String) -> String { "shared." + id }
    }

    init(live: Bool = true, defaults: UserDefaults = .standard,
         storeName: @escaping @MainActor (String) -> String = Suite.defaultStoreName,
         runsElsewhere: ((ModuleInfo) -> Bool)? = nil) {
        self.live = live
        self.defaults = defaults
        self.storeName = storeName
        self.runsElsewhere = runsElsewhere ?? { info in
            !NSRunningApplication.runningApplications(withBundleIdentifier: info.type.bundleIdentifier).isEmpty
        }
        // Until LongoKit has its own, a shared setting starts as in the modules' own apps (the first that has it).
        func saved(_ key: String) -> Any? {
            if let value = defaults.object(forKey: key) { return value }
            guard live else { return nil }
            return ModuleInfo.all.lazy.compactMap { UserDefaults.standard.persistentDomain(forName: $0.type.bundleIdentifier)?[key] }.first
        }
        language = (saved(Keys.language) as? String).flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
        appearance = (saved(Keys.appearance) as? String).flatMap(AppAppearance.init(rawValue:)) ?? .system
        showMenuBarIcon = saved(Keys.menuBarIcon) as? Bool ?? true
        if let saved = defaults.stringArray(forKey: Keys.modules) {
            enabled = Set(saved)
        } else {
            // The first time: the modules whose own apps have been used on this Mac.
            enabled = Set(ModuleInfo.all.filter { UserDefaults.standard.persistentDomain(forName: $0.type.bundleIdentifier) != nil }
                .map(\.id))
            defaults.set(enabled.sorted(), forKey: Keys.modules)
        }
        Localizer.language = language
        MainWindowRef.keepsDockIconWhenHidden = !showMenuBarIcon
        MainWindowRef.showModule = { [weak self] id in self?.open(id) }
        if let first = ModuleInfo.all.first(where: { enabled.contains($0.id) }) { page = .module(first.id) }
        // `--page display` opens on a given page (handy for screenshots).
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--page"), index + 1 < args.count {
            let name = args[index + 1]
            page = name == "general" ? .general : name == "about" ? .about : .module(name)
        }
        refreshStatuses()
    }

    // MARK: - Modules

    func status(_ id: String) -> Status {
        statuses[id] ?? .off
    }

    /// Runs the modules that are on, then keeps an eye on their own apps starting and quitting.
    func start() {
        applyAppearance()
        for info in ModuleInfo.all where enabled.contains(info.id) {
            // Set to start at login, LongoKit takes over from modules' own apps that start at login too.
            if live, startAtLogin, runsElsewhere(info) { quitOwnApp(info) }
            run(info)
        }
        guard live else { return }
        // A restart (turning a module off, a module needing it for a permission) waits for a recording to finish.
        AppLaunch.whenIdle = { [weak self] restart in self?.whenIdle(restart) }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                let launched = name == NSWorkspace.didLaunchApplicationNotification
                MainActor.assumeIsolated { self?.ownAppChanged(id, launched: launched) }
            })
        }
    }

    /// Turns a module on or off, at once: on loads it if it isn't yet; off stops it, and it isn't loaded next time.
    func setEnabled(_ info: ModuleInfo, _ on: Bool) {
        if on {
            enabled.insert(info.id)
            if let host = hosts[info.id] {
                if !host.isOn { host.setRunning(true) }
            } else {
                run(info, turnOn: true)
            }
        } else {
            enabled.remove(info.id)
            if let host = hosts[info.id], host.isOn { host.setRunning(false) }
        }
        refreshStatuses()
    }

    /// Quits a module's own app, so the module can run here; it starts once the app is gone.
    func quitOwnApp(_ info: ModuleInfo) {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: info.type.bundleIdentifier) {
            app.terminate()
        }
    }

    /// Opens the window on a module's page, and the menu on its controls.
    func open(_ id: String) {
        page = .module(id)
        if hosts[id] != nil { menuModule = id }
    }

    /// The module the menu bar popover shows: the last one picked, or else the first that's on.
    var menuInfo: ModuleInfo {
        ModuleInfo.named(menuModule ?? "")
            ?? ModuleInfo.all.first { status($0.id) == .running || status($0.id) == .attention } ?? ModuleInfo.all[0]
    }

    /// The switch each module showed last, to tell when the person flips it in the module itself.
    private var lastSwitch: [String: Bool] = [:]

    /// Loads a module that's on. `turnOn`: the person just turned it on, so its own switch goes on too; otherwise
    /// a module that was switched off in itself stays off.
    private func run(_ info: ModuleInfo, turnOn: Bool = false) {
        guard enabled.contains(info.id), hosts[info.id] == nil, !runsElsewhere(info) else { return refreshStatuses() }
        let store = UserDefaults(suiteName: storeName(info.id)) ?? .standard
        // LongoKit 0.1.3 and earlier kept a copy of its own: what was set there, the latest, moves to the shared one.
        if live, !defaults.bool(forKey: Keys.shared(info.id)) {
            defaults.set(true, forKey: Keys.shared(info.id))
            Self.moveSettings(from: "com.longokit.kit." + info.id, into: store)
        }
        let host = info.type.host(defaults: store, live: live)
        host.language = language
        host.appearance = appearance
        // Each module sets this from its own menu bar setting; LongoKit's is the one that counts.
        MainWindowRef.keepsDockIconWhenHidden = !showMenuBarIcon
        if turnOn && !host.isOn { host.setRunning(true) }
        lastSwitch[info.id] = host.isOn
        if !host.isOn { enabled.remove(info.id) }
        hosts[info.id] = host
        subscriptions[info.id] = host.changes.sink { [weak self] in self?.moduleChanged(info.id) }
        moduleChanged(info.id)
    }

    /// A module's own app's defaults domain.
    static func defaultStoreName(_ id: String) -> String {
        ModuleInfo.all.first { $0.id == id }?.type.bundleIdentifier ?? "com.longokit.kit." + id
    }

    /// Moves the settings kept in `domain` into `store`, over what's there, and removes `domain`.
    static func moveSettings(from domain: String, into store: UserDefaults) {
        guard let old = UserDefaults.standard.persistentDomain(forName: domain) else { return }
        for (key, value) in old { store.set(value, forKey: key) }
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }

    private func moduleChanged(_ id: String) {
        guard let host = hosts[id] else { return }
        // A module's theme switcher (in its menu) changes the whole app's appearance.
        if host.appearance != appearance { appearance = host.appearance }
        if host.language != language { language = host.language }
        // The module's own switch (in its menu or General tab) is the same switch as LongoKit's.
        if lastSwitch[id] != host.isOn {
            lastSwitch[id] = host.isOn
            if host.isOn { enabled.insert(id) } else { enabled.remove(id) }
        }
        // A module may set this from its own menu bar setting (say, restoring its defaults); LongoKit's counts.
        MainWindowRef.keepsDockIconWhenHidden = !showMenuBarIcon
        refreshStatuses()
        let image = ModuleInfo.all.lazy.compactMap { self.hosts[$0.id]?.menuBarImage }.first
        if image != nil || menuBarImage != nil { menuBarImage = image }
    }

    private func refreshStatuses() {
        var next: [String: Status] = [:]
        for info in ModuleInfo.all {
            if !enabled.contains(info.id) {
                next[info.id] = .off
            } else if let host = hosts[info.id] {
                next[info.id] = host.isRunning ? .running : .attention
            } else {
                next[info.id] = .elsewhere
            }
        }
        if next != statuses { statuses = next }
    }

    /// A module's own app started or quit.
    func ownAppChanged(_ bundleIdentifier: String?, launched: Bool) {
        guard let info = ModuleInfo.all.first(where: { $0.type.bundleIdentifier == bundleIdentifier }) else { return }
        if launched {
            if hosts[info.id] != nil {
                // At login both may start; set to start at login, LongoKit is the one to keep.
                if startAtLogin { quitOwnApp(info) } else { offerToQuitOwnApp(info) }
            }
            refreshStatuses()
        } else if enabled.contains(info.id) {
            // Its own app quit: the module takes over here, once macOS has let go of it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.run(info) }
        }
    }

    /// Both copies at once would act on every click and key twice.
    private func offerToQuitOwnApp(_ info: ModuleInfo) {
        let alert = NSAlert()
        alert.messageText = L("%@ is also open on its own", info.appName)
        alert.informativeText = L("LongoKit already runs %@. Both at once would act on everything twice.", info.title)
        alert.addButton(withTitle: L("Quit %@", info.appName))
        alert.addButton(withTitle: L("Keep Both"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { quitOwnApp(info) }
    }

    /// Runs `action` once no module is busy, checking every second.
    private func whenIdle(_ action: @escaping () -> Void) {
        guard hosts.values.contains(where: \.isBusy) else { return action() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.whenIdle(action) }
    }

    /// Lets every module finish up (a recording saved, displays back on, remaps cleared), then calls `done`.
    func prepareToQuit(_ done: @escaping () -> Void) {
        let running = Array(hosts.values)
        guard !running.isEmpty else { return done() }
        var left = running.count
        for host in running {
            host.prepareToQuit {
                left -= 1
                if left == 0 { done() }
            }
        }
    }

    // MARK: - App

    func setStartAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Start at login: \(error.localizedDescription)")
        }
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        startAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// NSApp may not exist yet during launch, so apply on the next turn of the run loop.
    private func applyAppearance() {
        let appearance = appearance.nsAppearance
        DispatchQueue.main.async { NSApp?.appearance = appearance }
    }
}
