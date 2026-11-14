import AppKit
import Combine
import LongoKitUI
import ServiceManagement
import SwiftUI

enum MainTab: CaseIterable {
    case devices, general, about

    var title: String {
        switch self {
        case .devices: return L("Macs")
        case .general: return L("General")
        case .about: return L("About")
        }
    }
}

/// Pairing as the person sees it.
enum Pairing: Equatable {
    case none
    /// Asking `name`: waiting for it to show a code.
    case asking(String)
    /// `name` shows a code to type here.
    case typing(String, wrong: Bool)
    /// `name` asked: this code is to be typed there.
    case showing(String, code: String)
}

/// Longo Flow's state: this Mac, the Macs paired with it and which are around, and where the keyboard and mouse are.
@MainActor
final class AppModel: ObservableObject, HostableModel {
    @Published var tab: MainTab = .devices
    @Published private(set) var nearby: [NearbyMac] = []
    @Published private(set) var paired: [PairedMac] = [] {
        didSet { save(paired, forKey: Keys.paired) }
    }
    @Published private(set) var connected: Set<String> = []
    /// The Mac the keyboard and mouse are on now (nil: this one).
    @Published private(set) var controlling: String?
    /// The Mac using this one's screen now.
    @Published private(set) var controlledBy: String?
    @Published private(set) var pairing = Pairing.none
    @Published private(set) var hasAccessibility = InputBridge.isTrusted
    @Published private(set) var lastPaired: String?

    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Keys.enabled)
            if isEnabled { start() } else { stop() }
        }
    }

    /// What's copied goes along with the pointer.
    @Published var sharesClipboard: Bool {
        didSet { defaults.set(sharesClipboard, forKey: Keys.clipboard) }
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
            let value = appearance.nsAppearance
            DispatchQueue.main.async { NSApp?.appearance = value }
        }
    }

    @Published var showMenuBarIcon: Bool {
        didSet {
            defaults.set(showMenuBarIcon, forKey: Keys.menuBarIcon)
            MainWindowRef.keepsDockIconWhenHidden = !showMenuBarIcon
        }
    }

    @Published private(set) var startAtLogin = SMAppService.mainApp.status == .enabled

    let name = Host.current().localizedName ?? "Mac"
    private let id: String
    private let defaults: UserDefaults
    private let live: Bool
    private var node: FlowNode?
    private let bridge = InputBridge()
    private let clipboard = Clipboard()
    private var accessTimer: Timer?

    private enum Keys {
        static let enabled = "enabled"
        static let id = "id"
        static let paired = "paired"
        static let clipboard = "sharesClipboard"
        static let language = "language"
        static let appearance = "appearance"
        static let menuBarIcon = "showMenuBarIcon"
    }

    init(live: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.live = live
        if let saved = defaults.string(forKey: Keys.id) {
            id = saved
        } else {
            id = UUID().uuidString
            defaults.set(id, forKey: Keys.id)
        }
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        sharesClipboard = defaults.object(forKey: Keys.clipboard) as? Bool ?? true
        paired = defaults.data(forKey: Keys.paired).flatMap { try? JSONDecoder().decode([PairedMac].self, from: $0) } ?? []
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .system
        showMenuBarIcon = defaults.object(forKey: Keys.menuBarIcon) as? Bool ?? true
        Localizer.language = language
        MainWindowRef.keepsDockIconWhenHidden = !showMenuBarIcon
        let value = appearance.nsAppearance
        DispatchQueue.main.async { NSApp?.appearance = value }
        if live { screenNames = Screens.names() }
        if live && isEnabled { start() }
    }

    // MARK: - Running

    private func start() {
        guard live, node == nil else { return }
        let node = FlowNode(id: id, name: name, paired: paired)
        node.nearbyChanged = { list in Task { @MainActor [weak self] in self?.nearby = list } }
        node.pairedChanged = { list in Task { @MainActor [weak self] in self?.pairedChanged(list) } }
        node.connectedChanged = { set in Task { @MainActor [weak self] in self?.connectedChanged(set) } }
        node.showCode = { code, from in Task { @MainActor [weak self] in self?.showCode(code, from) } }
        node.needsCode = { from in Task { @MainActor [weak self] in self?.pairing = .typing(from, wrong: false) } }
        node.codeRejected = { from in Task { @MainActor [weak self] in self?.pairing = .typing(from, wrong: true) } }
        node.pairingEnded = { name, ok in Task { @MainActor [weak self] in self?.pairingEnded(name, ok) } }
        // Events go straight to the bridge, off the main thread; the clipboard goes through the main one.
        node.localScreens = { Screens.all() }
        refreshWallpapers(node)
        node.placedThere = { mac in Task { @MainActor [weak self] in self?.placing.remove(mac) } }
        let bridge = self.bridge
        node.received = { [weak self] mac, message in
            if message.kind == .clipboard {
                Task { @MainActor in self?.clipboardArrived(message.payload) }
            } else if message.kind == .wallpaper {
                Task { @MainActor in self?.wallpaperArrived(message.payload, from: mac) }
            } else {
                bridge.received(message, from: mac)
            }
        }
        bridge.send = { [weak node] message, mac in node?.send(message, to: mac) }
        bridge.controlling = { mac in Task { @MainActor [weak self] in self?.controllingChanged(mac) } }
        bridge.controlledBy = { mac in Task { @MainActor [weak self] in self?.controlledByChanged(mac) } }
        self.node = node
        node.start()
        startBridge()
        // A display plugged in, moved or gone: the other Macs hear of it, and the edges here move.
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in
                self?.bridge.screensChanged()
                if let node = self?.node { self?.refreshWallpapers(node) }
                self?.node?.sendScreens()
                self?.arranging = false
                self?.settle()
                self?.localScreens = Screens.all()
                self?.screenNames = Screens.names()
                self?.localBuiltin = Screens.builtin(in: Screens.all())
            }
        }
    }

    private var screenObserver: NSObjectProtocol?
    /// This Mac's displays, for the arrangement.
    @Published private(set) var localScreens = Screens.all()
    /// Their names, for the arrangement.
    @Published private(set) var screenNames: [String: String] = [:]
    /// Each display's wallpaper here, and the other Macs' (as they sent them), for the arrangement.
    @Published private(set) var wallpapers: [NSImage?] = []
    @Published private(set) var theirWallpapers: [String: [Int: NSImage]] = [:]
    /// This Mac's displays are being moved (until macOS says they have).
    @Published private(set) var arranging = false
    private var settledOnce = false

    private func refreshWallpapers(_ node: FlowNode) {
        let pictures = Screens.wallpapers()
        node.localWallpapers = pictures
        let names = Screens.names()
        node.localNames = Screens.all().map { Screens.short(names[Screens.key($0)] ?? "") }
        wallpapers = pictures.map { $0.flatMap(NSImage.init(data:)) }
    }

    private func wallpaperArrived(_ payload: Data, from mac: String) {
        guard let index = payload.first, let picture = NSImage(data: payload.dropFirst()) else { return }
        theirWallpapers[mac, default: [:]][Int(index)] = picture
    }

    /// Moves this Mac's displays to `frames` (one dragged in the arrangement), as System Settings does. If the main
    /// display moved, everything shifted: the other Macs keep their places next to the displays.
    func arrange(_ frames: [CGRect]) {
        guard frames != localScreens else { return }
        arranging = true
        let shift = Screens.arrange(frames)
        if shift != .zero {
            for mac in paired {
                guard let offset = mac.offset else { continue }
                place(mac, at: CGPoint(x: offset.x + shift.x, y: offset.y + shift.y))
            }
        }
        // macOS says when it's done; if it doesn't, the arrangement shows what it has.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.arranging else { return }
            self.arranging = false
            self.localScreens = Screens.all()
        }
    }

    /// After this Mac's displays changed (moved, plugged in, gone): each other Mac back against them, touching and
    /// covering nothing (where it was may now be on top of a display, or away from them all).
    func settle() {
        var taken: [CGRect] = []
        for mac in paired {
            guard let offset = mac.offset, !mac.screens.isEmpty else { continue }
            let fixed = Screens.snap(mac.screens, at: offset, to: localScreens, avoiding: taken)
            taken += mac.screens.map { $0.offsetBy(dx: fixed.x, dy: fixed.y) }
            if hypot(fixed.x - offset.x, fixed.y - offset.y) > 0.5 { place(mac, at: fixed) }
        }
    }

    /// The other Macs' displays where they sit here, but `mac`'s.
    func placedScreens(except mac: String? = nil) -> [CGRect] {
        paired.filter { $0.id != mac }.flatMap { other in
            other.knownScreens.map { $0.offsetBy(dx: offset(of: other).x, dy: offset(of: other).y) }
        }
    }

    /// Which of this Mac's displays is its own (a laptop's).
    @Published private(set) var localBuiltin = Screens.builtin(in: Screens.all())

    private func stop() {
        bridge.stop()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        node?.stop()
        node = nil
        nearby = []
        connected = []
        controlling = nil
        controlledBy = nil
        pairing = .none
    }

    /// The event tap needs Accessibility: until it's granted, it's checked again every second.
    private func startBridge() {
        hasAccessibility = InputBridge.isTrusted
        if hasAccessibility {
            bridge.start()
            accessTimer?.invalidate()
            accessTimer = nil
            return
        }
        guard accessTimer == nil else { return }
        accessTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled, InputBridge.isTrusted else { return }
                self.startBridge()
            }
        }
    }

    func askForAccessibility() {
        InputBridge.askForAccess()
        startBridge()
    }

    private func pairedChanged(_ list: [PairedMac]) {
        paired = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        bridge.setPeers(peers)
    }

    private func connectedChanged(_ set: Set<String>) {
        connected = set
        bridge.setPeers(peers)
        // Joined with its displays known: if where it sits is on top of a display here, it moves off.
        if !settledOnce, paired.contains(where: { set.contains($0.id) && !$0.screens.isEmpty && $0.offset != nil }) {
            settledOnce = true
            settle()
        }
    }

    /// The connected Macs that know their screens and are placed.
    private var peers: [String: InputBridge.Peer] {
        var result: [String: InputBridge.Peer] = [:]
        for mac in paired where connected.contains(mac.id) && !mac.screens.isEmpty {
            guard let offset = mac.offset else { continue }
            result[mac.id] = InputBridge.Peer(screens: mac.screens, offset: offset)
        }
        return result
    }

    private func controllingChanged(_ mac: String?) {
        controlling = mac
        // What's copied here goes over with the pointer.
        if let mac, sharesClipboard, let payload = clipboard.changed() { node?.sendBulk(Message(.clipboard, payload), to: mac) }
    }

    private func controlledByChanged(_ mac: String?) {
        let was = controlledBy
        controlledBy = mac
        // ...and what was copied over there comes back with it.
        if mac == nil, let was, sharesClipboard, let payload = clipboard.changed() { node?.sendBulk(Message(.clipboard, payload), to: was) }
    }

    private func clipboardArrived(_ payload: Data) {
        guard sharesClipboard else { return }
        clipboard.set(payload)
    }

    // MARK: - Pairing

    func pair(with mac: NearbyMac, side: Side = .right) {
        pairing = .asking(mac.name)
        node?.pair(with: mac.id, side: side)
    }

    func submit(code: String) {
        node?.submit(code: code)
    }

    func cancelPairing() {
        pairing = .none
        node?.cancelPairing()
    }

    private func showCode(_ code: String?, _ from: String) {
        if let code {
            pairing = .showing(from, code: code)
            tab = .devices
            MainWindowRef.show(module: FlowModule.id)
        } else if case .showing = pairing {
            pairing = .none
        }
    }

    private func pairingEnded(_ name: String, _ ok: Bool) {
        if case .showing = pairing, !ok { return }
        pairing = .none
        if ok { lastPaired = name }
    }

    /// Macs just moved in the arrangement, until they say they have it.
    @Published private(set) var placing: Set<String> = []

    /// Puts a Mac's screens at `offset` here (dragged in the arrangement), here and there.
    func place(_ mac: PairedMac, at offset: CGPoint) {
        if let index = paired.firstIndex(where: { $0.id == mac.id }) { paired[index].offset = offset }
        node?.place(mac.id, at: offset)
        // Connected, it confirms; if it doesn't within a few seconds, it'll get the arrangement when it next connects.
        guard connected.contains(mac.id) else { return }
        placing.insert(mac.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.placing.remove(mac.id) }
    }

    /// Where a Mac sits here: as placed, or by its side until it is.
    func offset(of mac: PairedMac) -> CGPoint {
        mac.offset ?? mac.placed(next: localScreens)
    }

    func unpair(_ mac: PairedMac) {
        node?.unpair(mac.id)
    }

    /// Paired Macs, then the others around.
    var unpairedNearby: [NearbyMac] {
        let known = Set(paired.map(\.id))
        return nearby.filter { !known.contains($0.id) }
    }

    func name(of mac: String?) -> String {
        guard let mac else { return "" }
        return paired.first { $0.id == mac }?.name ?? nearby.first { $0.id == mac }?.name ?? ""
    }

    // MARK: - App

    func setStartAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Start at login failed: \(error.localizedDescription)")
        }
        startAtLogin = SMAppService.mainApp.status == .enabled
    }

    func prepareToQuit() {
        stop()
    }

    /// Macs, for snapshots.
    func simulate(nearby: [NearbyMac], paired: [PairedMac], connected: Set<String>, pairing: Pairing = .none, access: Bool = true,
                  screens: [CGRect]? = nil) {
        if let screens {
            localScreens = screens
            localBuiltin = screens.firstIndex { $0.minX == 0 && $0.minY == 0 }
        }
        screenNames = [:]
        self.nearby = nearby
        self.paired = paired
        self.connected = connected
        self.pairing = pairing
        hasAccessibility = access
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        if live, let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}

/// What's copied, going over: text or a picture, sent when it changed since it last went (or came) over.
final class Clipboard {
    private var synced = NSPasteboard.general.changeCount

    /// What's on the clipboard, if it changed since it last went over.
    func changed() -> Data? {
        let board = NSPasteboard.general
        guard board.changeCount != synced else { return nil }
        synced = board.changeCount
        // As it is (no converting a big picture on the way over, which would hold the app up).
        if let png = board.data(forType: .png), png.count < 32 << 20 { return Data([1]) + png }
        if let tiff = board.data(forType: .tiff), tiff.count < 32 << 20 { return Data([2]) + tiff }
        if let text = board.string(forType: .string) {
            return Data([0]) + Data(text.utf8)
        }
        return nil
    }

    func set(_ payload: Data) {
        guard let kind = payload.first else { return }
        let body = payload.dropFirst()
        let board = NSPasteboard.general
        board.clearContents()
        switch kind {
        case 0: board.setString(String(decoding: body, as: UTF8.self), forType: .string)
        case 1: board.setData(Data(body), forType: .png)
        case 2: board.setData(Data(body), forType: .tiff)
        default: break
        }
        synced = board.changeCount
    }

}

extension Side {
    var title: String {
        switch self {
        case .left: return L("Left")
        case .right: return L("Right")
        case .top: return L("Above")
        case .bottom: return L("Below")
        }
    }
}
