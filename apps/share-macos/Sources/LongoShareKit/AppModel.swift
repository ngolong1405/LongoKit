import AppKit
import Combine
import LongoKitUI
import ServiceManagement
import SwiftUI

enum MainTab: CaseIterable {
    case devices, general, about

    var title: String {
        switch self {
        case .devices: return L("Devices")
        case .general: return L("General")
        case .about: return L("About")
        }
    }
}

/// A device whose files come in without asking.
struct TrustedDevice: Codable, Hashable {
    var fingerprint: String
    var alias: String
}

/// A file in a chat: its name and size, and where it is on this Mac (sent from, or saved to).
struct ChatFile: Codable, Hashable {
    var name: String
    var size: Int64
    var path: String?
}

/// Where a message stands.
enum ChatState: String, Codable {
    /// Coming in, waiting for the person here to accept or decline.
    case asking
    /// Going out, waiting for the other side to accept.
    case waiting
    /// The other side wants a PIN before it takes these.
    case pin
    case transferring, done, declined, failed, cancelled
}

/// One message in a chat with a device: text, or files, either way.
struct ChatItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var sent: Bool
    var text: String?
    var files: [ChatFile] = []
    var state: ChatState
    var time = Date()
    var done: Int64 = 0
    var total: Int64 = 0

    var fraction: Double { total == 0 ? 0 : min(1, Double(done) / Double(total)) }
    var isOpen: Bool { [.asking, .waiting, .pin, .transferring].contains(state) }
}

/// The chat with one device, kept across launches (the device may not be around now).
struct Conversation: Codable, Hashable, Identifiable {
    var id: String
    var alias: String
    var deviceModel: String?
    var deviceType: String?
    var items: [ChatItem] = []
    var unread = 0

    var lastTime: Date { items.last?.time ?? .distantPast }
}

/// A transfer under way, for the menu bar and the title bar.
struct Transfer: Equatable {
    var device: String
    var sending: Bool
    var done: Int64
    var total: Int64

    var fraction: Double { total == 0 ? 0 : min(1, Double(done) / Double(total)) }
}

/// A device in the list: one around now, or one chatted with before.
struct Contact: Identifiable, Hashable {
    var id: String
    var info: DeviceInfo
    /// Where it is now; nil when it isn't around.
    var peer: Peer?
    var conversation: Conversation?

    var isOnline: Bool { peer != nil }
}

/// Longo Share's state: the settings, the device (`ShareNode`) while it's on, the devices around, and a chat with
/// each one, where files and text come and go and incoming transfers are answered.
@MainActor
final class AppModel: ObservableObject, HostableModel {
    @Published var tab: MainTab = .devices
    @Published private(set) var peers: [Peer] = []
    @Published private(set) var conversations: [String: Conversation] = [:] {
        didSet { scheduleSave() }
    }
    /// The chat on screen.
    @Published var selected: String? {
        didSet { markRead() }
    }
    /// Why it can't receive (the port is taken...), or nil.
    @Published private(set) var problem: String?
    @Published private(set) var isScanning = false
    @Published private(set) var lastAddressFailed: String?

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
    private(set) var problemDetail = ""

    private let defaults: UserDefaults
    private let live: Bool
    private let fingerprint: String
    private var node: ShareNode?
    private var sending: [UUID: Task<Void, Never>] = [:]
    private var announcer: Timer?
    /// Answers the person gives in a chat: an incoming request's, or a PIN.
    private var answers: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var pins: [UUID: CheckedContinuation<String?, Never>] = [:]
    /// The incoming transfer under way: its chat and message.
    private var incoming: (conversation: String, item: UUID)?
    private var lastProgress = Date.distantPast
    private var saveTask: Task<Void, Never>?

    private enum Keys {
        static let enabled = "enabled"
        static let alias = "alias"
        static let folder = "folder"
        static let pin = "pin"
        static let trusted = "trusted"
        static let conversations = "conversations"
        static let fingerprint = "fingerprint"
        static let language = "language"
        static let appearance = "appearance"
        static let menuBarIcon = "showMenuBarIcon"
    }

    /// Messages kept per chat.
    private static let chatLength = 300

    init(live: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.live = live
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        alias = defaults.string(forKey: Keys.alias) ?? Host.current().localizedName ?? "Mac"
        // Its own folder in Downloads, so what came in is easy to find (0.1.0 saved straight to Downloads).
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let savedFolder = defaults.string(forKey: Keys.folder).map { URL(fileURLWithPath: $0) }
        folder = savedFolder == nil || savedFolder!.standardizedFileURL == downloads.standardizedFileURL
            ? downloads.appendingPathComponent("Longo Share", isDirectory: true) : savedFolder!
        pin = defaults.string(forKey: Keys.pin)
        trusted = defaults.data(forKey: Keys.trusted).flatMap { try? JSONDecoder().decode([TrustedDevice].self, from: $0) } ?? []
        var saved = defaults.data(forKey: Keys.conversations).flatMap { try? JSONDecoder().decode([String: Conversation].self, from: $0) } ?? [:]
        // What was under way when the app quit didn't finish.
        for key in saved.keys {
            for index in saved[key]!.items.indices where saved[key]!.items[index].isOpen {
                saved[key]!.items[index].state = .failed
            }
        }
        conversations = saved
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

    // MARK: - Devices

    /// This Mac, as others see it.
    var address: String { Discovery.localAddresses().first.map { Discovery.text($0.address) } ?? "" }

    /// Devices around now first, then the ones chatted with before, most recent first.
    var contacts: [Contact] {
        var list = peers.map { Contact(id: $0.id, info: $0.info, peer: $0, conversation: conversations[$0.id]) }
        let online = Set(list.map(\.id))
        for conversation in conversations.values where !online.contains(conversation.id) {
            list.append(Contact(id: conversation.id,
                                info: DeviceInfo(alias: conversation.alias, deviceModel: conversation.deviceModel,
                                                 deviceType: conversation.deviceType, fingerprint: conversation.id),
                                peer: nil, conversation: conversation))
        }
        return list.sorted { a, b in
            if a.isOnline != b.isOnline { return a.isOnline }
            let at = a.conversation?.lastTime ?? .distantPast, bt = b.conversation?.lastTime ?? .distantPast
            if at != bt { return at > bt }
            return a.info.alias.localizedCaseInsensitiveCompare(b.info.alias) == .orderedAscending
        }
    }

    func contact(_ id: String?) -> Contact? {
        guard let id else { return nil }
        return contacts.first { $0.id == id }
    }

    var unread: Int { conversations.values.reduce(0) { $0 + $1.unread } }

    /// The transfer under way, if any.
    var current: Transfer? {
        for conversation in conversations.values {
            if let item = conversation.items.last(where: { $0.state == .transferring }) {
                return Transfer(device: conversation.alias, sending: item.sent, done: item.done, total: item.total)
            }
        }
        return nil
    }

    /// Opens the window on a device's chat.
    func open(_ id: String) {
        tab = .devices
        selected = id
        MainWindowRef.show()
    }

    // MARK: - Running

    private func start() {
        guard live, node == nil else { return }
        let node = ShareNode(settings: ShareSettings(alias: alias, fingerprint: fingerprint, folder: folder, pin: pin,
                                                     trusted: Set(trusted.map(\.fingerprint))))
        let receiver = node.receiver
        receiver.ask = { [weak self] transfer in
            if transfer.text != nil { return true }
            return await self?.askToAccept(transfer) ?? false
        }
        receiver.accepted = { [weak self] transfer in Task { @MainActor in self?.accepted(transfer) } }
        receiver.progress = { [weak self] done, total in Task { @MainActor in self?.receiving(done, total) } }
        receiver.received = { [weak self] received in Task { @MainActor in self?.received(received) } }
        receiver.cancelled = { [weak self] in Task { @MainActor in self?.incomingEnded() } }
        node.peersChanged = { [weak self] in Task { @MainActor in self?.peersChanged() } }
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

    private func stop() {
        stopNode()
        problem = nil
    }

    private func stopNode() {
        announcer?.invalidate()
        announcer = nil
        for task in sending.values { task.cancel() }
        for (id, answer) in answers { answer.resume(returning: false); update(id) { $0.state = .cancelled } }
        answers = [:]
        for (_, pin) in pins { pin.resume(returning: nil) }
        pins = [:]
        node?.stop()
        node = nil
        peers = []
    }

    private func peersChanged() {
        peers = node?.list ?? []
        // A device's chat follows its new name.
        for peer in peers where conversations[peer.id] != nil && conversations[peer.id]?.alias != peer.info.alias {
            conversations[peer.id]?.alias = peer.info.alias
        }
        if selected == nil, let first = peers.first { selected = first.id }
    }

    /// Looks for devices: an announcement, then every address on the network.
    func refresh() async {
        guard let node, !isScanning else { return }
        isScanning = true
        await node.refresh()
        peersChanged()
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
        peersChanged()
        lastAddressFailed = peer == nil ? address : nil
        if let peer { selected = peer.id }
    }

    // MARK: - Chats

    private func conversation(for info: DeviceInfo, id: String) {
        if conversations[id] == nil {
            conversations[id] = Conversation(id: id, alias: info.alias, deviceModel: info.deviceModel, deviceType: info.deviceType)
        }
    }

    private func append(_ item: ChatItem, to id: String, from info: DeviceInfo) {
        conversation(for: info, id: id)
        conversations[id]!.items.append(item)
        if conversations[id]!.items.count > Self.chatLength { conversations[id]!.items.removeFirst(conversations[id]!.items.count - Self.chatLength) }
        if !item.sent {
            // Seen at once when its chat is open in a window on screen; otherwise the window comes up on it.
            let onScreen = WindowVisibility.shared.isShown && MainWindowRef.window?.isVisible == true && tab == .devices
            if onScreen && selected == id { return }
            conversations[id]!.unread += 1
            if !onScreen && live { open(id) } else if selected == nil { selected = id }
        }
    }

    private func update(_ item: UUID, _ change: (inout ChatItem) -> Void) {
        for key in conversations.keys {
            if let index = conversations[key]!.items.firstIndex(where: { $0.id == item }) {
                change(&conversations[key]!.items[index])
                return
            }
        }
    }

    private func markRead() {
        guard let selected, conversations[selected]?.unread ?? 0 > 0 else { return }
        conversations[selected]!.unread = 0
    }

    func clear(_ id: String) {
        conversations[id]?.items.removeAll { !$0.isOpen }
        if conversations[id]?.items.isEmpty == true, peers.contains(where: { $0.id == id }) == false { conversations[id] = nil }
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
        guard !files.isEmpty else { return }
        let chatFiles = files.map { ChatFile(name: $0.lastPathComponent, size: Int64((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), path: $0.path) }
        send(files.map(Outgoing.file), item: ChatItem(sent: true, files: chatFiles, state: .waiting, total: chatFiles.reduce(0) { $0 + $1.size }), to: peer)
    }

    func send(text: String, to peer: Peer) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        send([.message(text)], item: ChatItem(sent: true, text: text, state: .waiting, total: Int64(text.utf8.count)), to: peer)
    }

    private func send(_ items: [Outgoing], item: ChatItem, to peer: Peer) {
        guard let node else { return }
        append(item, to: peer.id, from: peer.info)
        let id = item.id
        sending[id] = Task {
            var pin: String?
            var result: SendResult
            while true {
                result = await node.send(to: peer, items: items, pin: pin) { [weak self] done, all in
                    Task { @MainActor in self?.progressed(id, done, all) }
                }
                if Task.isCancelled { result = .cancelled }
                guard result == .pinRequired else { break }
                update(id) { $0.state = .pin }
                pin = await withCheckedContinuation { pins[id] = $0 }
                if pin == nil {
                    result = .cancelled
                    break
                }
                update(id) { $0.state = .waiting }
            }
            sending[id] = nil
            update(id) { item in
                switch result {
                case .sent: item.state = .done; item.done = item.total
                case .rejected: item.state = .declined
                case .busy, .failed, .pinRequired: item.state = .failed
                case .cancelled: item.state = .cancelled
                }
            }
        }
    }

    /// The PIN the other side asked for (nil gives up).
    func answerPin(_ item: UUID, _ pin: String?) {
        pins.removeValue(forKey: item)?.resume(returning: pin)
    }

    /// Stops a message under way, either way.
    func cancel(_ item: UUID) {
        if let task = sending[item] {
            task.cancel()
            answerPin(item, nil)
        } else if let incoming, incoming.item == item {
            node?.receiver.cancel()
        }
    }

    private func progressed(_ id: UUID, _ done: Int64, _ total: Int64) {
        guard sending[id] != nil else { return }
        let now = Date()
        if now.timeIntervalSince(lastProgress) < 0.1 && done < total { return }
        lastProgress = now
        update(id) { item in
            item.state = .transferring
            item.done = done
            item.total = total
        }
    }

    // MARK: - Receiving

    private func askToAccept(_ transfer: IncomingTransfer) async -> Bool {
        let peer = transfer.from
        let item = ChatItem(sent: false, files: transfer.files.map { ChatFile(name: $0.fileName, size: $0.size) }, state: .asking,
                            total: transfer.files.reduce(0) { $0 + $1.size })
        append(item, to: peer.id, from: peer.info)
        let accepted = await withCheckedContinuation { answers[item.id] = $0 }
        if accepted { incoming = (peer.id, item.id) }
        return accepted
    }

    /// The person's answer to files coming in; `always` trusts the device from then on.
    func answer(_ item: UUID, accept: Bool, always: Bool = false) {
        guard let answer = answers.removeValue(forKey: item) else { return }
        update(item) { $0.state = accept ? .transferring : .declined }
        if accept && always, let id = conversations.first(where: { $0.value.items.contains { $0.id == item } })?.key,
           let contact = contact(id) {
            setTrusted(contact.info, true)
        }
        answer.resume(returning: accept)
    }

    /// Files on their way in; from a trusted device, their message starts here.
    private func accepted(_ transfer: IncomingTransfer) {
        if incoming != nil { return }
        let item = ChatItem(sent: false, files: transfer.files.map { ChatFile(name: $0.fileName, size: $0.size) }, state: .transferring,
                            total: transfer.files.reduce(0) { $0 + $1.size })
        append(item, to: transfer.from.id, from: transfer.from.info)
        incoming = (transfer.from.id, item.id)
    }

    private func receiving(_ done: Int64, _ total: Int64) {
        guard let incoming else { return }
        let now = Date()
        if now.timeIntervalSince(lastProgress) < 0.1 && done < total { return }
        lastProgress = now
        update(incoming.item) { item in
            item.state = .transferring
            item.done = done
            item.total = total
        }
    }

    private func received(_ received: ReceivedTransfer) {
        if let text = received.text {
            append(ChatItem(sent: false, text: text, state: .done), to: received.from.id, from: received.from.info)
            return
        }
        guard let incoming else { return }
        self.incoming = nil
        update(incoming.item) { item in
            item.state = .done
            item.done = item.total
            // Saved under their own names (photo (1).jpg when there was one already).
            item.files = received.files.map { url in
                ChatFile(name: url.lastPathComponent, size: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), path: url.path)
            }
        }
    }

    private func incomingEnded() {
        guard let incoming else { return }
        self.incoming = nil
        update(incoming.item) { $0.state = .failed }
    }

    // MARK: - Trust

    func isTrusted(_ info: DeviceInfo) -> Bool { trusted.contains { $0.fingerprint == info.fingerprint } }

    func setTrusted(_ info: DeviceInfo, _ on: Bool) {
        guard !info.fingerprint.isEmpty else { return }
        var list = trusted.filter { $0.fingerprint != info.fingerprint }
        if on { list.append(TrustedDevice(fingerprint: info.fingerprint, alias: info.alias)) }
        trusted = list
    }

    func forget(_ device: TrustedDevice) {
        trusted.removeAll { $0.fingerprint == device.fingerprint }
    }

    // MARK: - App

    /// A transfer is under way: quitting would cut it short.
    var isBusy: Bool { current != nil }

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
        saveNow()
    }

    /// Devices and chats, for snapshots.
    func simulate(peers: [Peer], conversations: [Conversation], selected: String?, trusted: [TrustedDevice]) {
        self.peers = peers
        self.conversations = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
        self.selected = selected
        self.trusted = trusted
    }

    private func applyAppearance() {
        let appearance = appearance.nsAppearance
        DispatchQueue.main.async { NSApp?.appearance = appearance }
    }

    /// Chats change at every bit of progress: they're written a moment later, once.
    private func scheduleSave() {
        guard live else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled { self?.saveNow() }
        }
    }

    private func saveNow() {
        save(conversations, forKey: Keys.conversations)
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
