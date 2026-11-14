import AppKit
import Combine
import LongoKitUI
import ServiceManagement
import SwiftUI

enum MainTab: CaseIterable {
    case general, devices, history, about

    var title: String {
        switch self {
        case .general: return L("General")
        case .devices: return L("Devices")
        case .history: return L("History")
        case .about: return L("About")
        }
    }
}

/// A device whose files come in without asking.
struct TrustedDevice: Codable, Hashable {
    var fingerprint: String
    var alias: String
}

/// A transfer done, for History.
struct HistoryItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var sent: Bool
    var device: String
    var files: [String] = []
    /// Where received files went.
    var folder: String?
    var text: String?
    var time: Date
}

/// A transfer under way.
struct Transfer: Equatable {
    var device: String
    var sending: Bool
    var done: Int64
    var total: Int64

    var fraction: Double { total == 0 ? 0 : min(1, Double(done) / Double(total)) }
}

/// What happened last: an English line (through L) about a device.
struct Notice: Equatable {
    var text: String
    var device = ""
    var good = true
}

/// Longo Share's state: the settings, the device (`ShareNode`) while it's on, the devices around, the transfer
/// under way and the history.
@MainActor
final class AppModel: ObservableObject, HostableModel {
    @Published var tab: MainTab = .general
    @Published private(set) var peers: [Peer] = []
    @Published private(set) var current: Transfer?
    @Published private(set) var notice: Notice?
    /// Why it can't receive (the port is taken...), or nil.
    @Published private(set) var problem: String?
    @Published private(set) var isScanning = false

    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Keys.enabled)
            if isEnabled { start() } else { stop() }
        }
    }

    @Published var alias: String {
        didSet {
            let trimmed = alias.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed != alias {
                alias = trimmed.isEmpty ? oldValue : trimmed
                return
            }
            defaults.set(alias, forKey: Keys.alias)
            node?.settings.alias = alias
            Task { await node?.refresh(scan: false) }
        }
    }

    @Published var folder: URL {
        didSet {
            defaults.set(folder.path, forKey: Keys.folder)
            node?.settings.folder = folder
        }
    }

    /// A PIN senders must give, or nil.
    @Published var pin: String? {
        didSet {
            let cleaned = pin?.trimmingCharacters(in: .whitespaces)
            if cleaned != pin || cleaned == "" {
                pin = cleaned?.isEmpty == true ? nil : cleaned
                return
            }
            defaults.set(pin, forKey: Keys.pin)
            node?.settings.pin = pin
        }
    }

    @Published private(set) var trusted: [TrustedDevice] {
        didSet {
            save(trusted, forKey: Keys.trusted)
            node?.settings.trusted = Set(trusted.map(\.fingerprint))
        }
    }

    @Published private(set) var history: [HistoryItem] {
        didSet { save(history, forKey: Keys.history) }
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

    /// Asks the person whether to take files; true takes them, and `always` trusts the device too.
    var ask: (IncomingTransfer) async -> (accept: Bool, always: Bool) = { _ in (false, false) }
    /// Asks for the PIN a device wants; nil gives up.
    var askPin: (Peer) async -> String? = { _ in nil }
    /// A message came in: shows it.
    var showMessage: (Peer, String) -> Void = { _, _ in }

    private let defaults: UserDefaults
    private let live: Bool
    private let fingerprint: String
    private var node: ShareNode?
    private var sending: Task<Void, Never>?
    private var announcer: Timer?
    private var receivingFrom = ""
    private var lastProgress = Date.distantPast

    private enum Keys {
        static let enabled = "enabled"
        static let alias = "alias"
        static let folder = "folder"
        static let pin = "pin"
        static let trusted = "trusted"
        static let history = "history"
        static let fingerprint = "fingerprint"
        static let language = "language"
        static let appearance = "appearance"
        static let menuBarIcon = "showMenuBarIcon"
    }

    private static let historyLength = 100

    init(live: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.live = live
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        alias = defaults.string(forKey: Keys.alias) ?? Host.current().localizedName ?? "Mac"
        folder = defaults.string(forKey: Keys.folder).map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        pin = defaults.string(forKey: Keys.pin)
        trusted = defaults.data(forKey: Keys.trusted).flatMap { try? JSONDecoder().decode([TrustedDevice].self, from: $0) } ?? []
        history = defaults.data(forKey: Keys.history).flatMap { try? JSONDecoder().decode([HistoryItem].self, from: $0) } ?? []
        language = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .system
        showMenuBarIcon = defaults.object(forKey: Keys.menuBarIcon) as? Bool ?? true
        // Receiving over plain HTTP, the fingerprint is a random id kept for good (LocalSend's way without a certificate).
        if let saved = defaults.string(forKey: Keys.fingerprint) {
            fingerprint = saved
        } else {
            fingerprint = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            defaults.set(fingerprint, forKey: Keys.fingerprint)
        }
        Localizer.language = language
        MainWindowRef.keepsDockIconWhenHidden = !showMenuBarIcon
        applyAppearance()
        if live && isEnabled { start() }
    }

    // MARK: - Running

    /// This Mac, as others see it.
    var address: String { Discovery.localAddresses().first.map { Discovery.text($0.address) } ?? "" }

    private func start() {
        guard live, node == nil else { return }
        let node = ShareNode(settings: ShareSettings(alias: alias, fingerprint: fingerprint, folder: folder, pin: pin,
                                                     trusted: Set(trusted.map(\.fingerprint))))
        let receiver = node.receiver
        receiver.ask = { [weak self] transfer in
            if transfer.text != nil { return true }
            return await self?.askToAccept(transfer) ?? false
        }
        receiver.accepted = { [weak self] transfer in Task { @MainActor in self?.receivingFrom = transfer.from.info.alias } }
        receiver.progress = { [weak self] done, total in
            Task { @MainActor in self?.progressed(Transfer(device: self?.receivingFrom ?? "", sending: false, done: done, total: total)) }
        }
        receiver.received = { [weak self] received in Task { @MainActor in self?.received(received) } }
        receiver.cancelled = { [weak self] in Task { @MainActor in self?.finish(Notice(text: "Transfer stopped.", good: false)) } }
        node.peersChanged = { [weak self] in Task { @MainActor in self?.peers = self?.node?.list ?? [] } }
        self.node = node
        problem = nil
        node.start { [weak self] error in
            Task { @MainActor in
                guard let self, let error else { return }
                self.problemDetail = error.localizedDescription
                self.problem = "\(error)".contains("48") || "\(error)".localizedCaseInsensitiveContains("in use")
                    ? "Port %d is taken by another app (LocalSend?). Quit it, then turn Longo Share off and on."
                    : "Couldn't start receiving: %@"
                self.stopNode()
            }
        }
        // Now and then, an announcement: others answer, and those that left drop off the list.
        announcer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.node?.refresh(scan: false) }
        }
        Task { await refresh() }
    }

    private(set) var problemDetail = ""

    private func stop() {
        stopNode()
        problem = nil
    }

    private func stopNode() {
        announcer?.invalidate()
        announcer = nil
        sending?.cancel()
        node?.stop()
        node = nil
        peers = []
        current = nil
    }

    /// Looks for devices: an announcement, then every address on the network.
    func refresh() async {
        guard let node, !isScanning else { return }
        isScanning = true
        await node.refresh()
        peers = node.list
        isScanning = false
    }

    /// Adds a device by its address, for when it isn't found on its own.
    func connect(_ text: String) async {
        guard let node else { return }
        var address = text.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }
        var port = ShareProtocol.port
        if address.filter({ $0 == ":" }).count == 1, let colon = address.lastIndex(of: ":"), let typed = Int(address[address.index(after: colon)...]) {
            port = typed
            address = String(address[..<colon])
        }
        let peer = await node.connect(address, port: port)
        peers = node.list
        notice = peer.map { Notice(text: "Found %@.", device: $0.info.alias) } ?? Notice(text: "Nothing answered at %@.", device: address, good: false)
    }

    // MARK: - Sending

    func send(_ urls: [URL], to peer: Peer) {
        // Folders send what's in them.
        var files: [URL] = []
        for url in urls {
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { continue }
            if isFolder.boolValue {
                let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                while let item = walker?.nextObject() as? URL {
                    if (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { files.append(item) }
                }
            } else {
                files.append(url)
            }
        }
        send(files.map(Outgoing.file), to: peer)
    }

    func send(text: String, to peer: Peer) {
        guard !text.isEmpty else { return }
        send([.message(text)], to: peer)
    }

    private func send(_ items: [Outgoing], to peer: Peer) {
        guard let node, !items.isEmpty, current == nil else { return }
        let total = items.reduce(Int64(0)) { sum, item in
            switch item {
            case .message(let text): return sum + Int64(text.utf8.count)
            case .file(let url): return sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        let name = peer.info.alias
        current = Transfer(device: name, sending: true, done: 0, total: total)
        notice = nil
        sending = Task {
            var pin: String?
            var result: SendResult
            while true {
                result = await node.send(to: peer, items: items, pin: pin) { [weak self] done, all in
                    Task { @MainActor in self?.progressed(Transfer(device: name, sending: true, done: done, total: all)) }
                }
                if Task.isCancelled { result = .cancelled }
                guard result == .pinRequired else { break }
                pin = await askPin(peer)
                if pin == nil {
                    result = .cancelled
                    break
                }
            }
            sending = nil
            if result == .sent {
                var files: [String] = []
                var text: String?
                for item in items {
                    switch item {
                    case .file(let url): files.append(url.lastPathComponent)
                    case .message(let message): text = message
                    }
                }
                remember(HistoryItem(sent: true, device: name, files: files, text: text, time: Date()))
            }
            switch result {
            case .sent: finish(Notice(text: "Sent to %@.", device: name))
            case .rejected: finish(Notice(text: "%@ declined.", device: name, good: false))
            case .busy: finish(Notice(text: "%@ is busy with another transfer.", device: name, good: false))
            case .cancelled: finish(Notice(text: "Cancelled."))
            case .failed, .pinRequired: finish(Notice(text: "Couldn't reach %@.", device: name, good: false))
            }
        }
    }

    /// Stops the transfer under way, either way.
    func cancel() {
        if let sending { sending.cancel() } else { node?.receiver.cancel() }
    }

    // MARK: - Receiving

    private func askToAccept(_ transfer: IncomingTransfer) async -> Bool {
        let answer = await ask(transfer)
        if answer.accept && answer.always { setTrusted(transfer.from, true) }
        return answer.accept
    }

    private func received(_ received: ReceivedTransfer) {
        remember(HistoryItem(sent: false, device: received.from.info.alias, files: received.files.map(\.lastPathComponent),
                             folder: received.files.first?.deletingLastPathComponent().path, text: received.text, time: Date()))
        if let text = received.text {
            showMessage(received.from, text)
            return
        }
        finish(Notice(text: "Received from %@.", device: received.from.info.alias))
    }

    private func progressed(_ transfer: Transfer) {
        // Each piece's message may land after the transfer has finished.
        if transfer.sending, sending == nil { return }
        if !transfer.sending, node?.receiver.isBusy != true { return }
        let now = Date()
        if now.timeIntervalSince(lastProgress) < 0.1 && transfer.done < transfer.total { return }
        lastProgress = now
        current = transfer
    }

    private func finish(_ notice: Notice) {
        current = nil
        self.notice = notice
    }

    private func remember(_ item: HistoryItem) {
        history.insert(item, at: 0)
        if history.count > Self.historyLength { history.removeLast(history.count - Self.historyLength) }
    }

    func clearHistory() { history = [] }

    /// A transfer is under way: quitting would cut it short.
    var isBusy: Bool { current != nil }

    // MARK: - Trust

    func isTrusted(_ peer: Peer) -> Bool { trusted.contains { $0.fingerprint == peer.info.fingerprint } }

    func setTrusted(_ peer: Peer, _ on: Bool) {
        guard !peer.info.fingerprint.isEmpty else { return }
        var list = trusted.filter { $0.fingerprint != peer.info.fingerprint }
        if on { list.append(TrustedDevice(fingerprint: peer.info.fingerprint, alias: peer.info.alias)) }
        trusted = list
    }

    func forget(_ device: TrustedDevice) {
        trusted.removeAll { $0.fingerprint == device.fingerprint }
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
        stopNode()
    }

    /// Devices, a transfer and a notice, for snapshots.
    func simulate(peers: [Peer], current: Transfer?, notice: Notice?, history: [HistoryItem], trusted: [TrustedDevice]) {
        self.peers = peers
        self.current = current
        self.notice = notice
        self.history = history
        self.trusted = trusted
    }

    private func applyAppearance() {
        let appearance = appearance.nsAppearance
        DispatchQueue.main.async { NSApp?.appearance = appearance }
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
