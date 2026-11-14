import Foundation

/// How this device shows itself and takes files.
public struct ShareSettings: Sendable {
    public var alias: String
    public var fingerprint: String
    public var folder: URL
    public var pin: String?
    /// Devices whose files come in without asking, by fingerprint.
    public var trusted: Set<String>
    public var port = ShareProtocol.port

    public init(alias: String, fingerprint: String, folder: URL, pin: String? = nil, trusted: Set<String> = []) {
        self.alias = alias
        self.fingerprint = fingerprint
        self.folder = folder
        self.pin = pin
        self.trusted = trusted
    }
}

/// One device on the network: its server (receiving, over plain HTTP for now), its client (sending, to HTTP or
/// HTTPS devices) and discovery, with the devices it knows. The UI drives this.
public final class ShareNode: @unchecked Sendable {
    private let lock = NSLock()
    private var _settings: ShareSettings
    private var peers: [String: (peer: Peer, seen: Date)] = [:]
    private var server: HTTPServer?
    private var discovery: Discovery?
    let receiver: Receiver
    let sender: Sender

    /// The device list changed.
    public var peersChanged: @Sendable () -> Void = {}

    public init(settings: ShareSettings) {
        _settings = settings
        var me: (@Sendable () -> DeviceInfo)!
        receiver = Receiver(me: { me() }, folder: settings.folder)
        sender = Sender(me: { me() })
        me = { [unowned self] in self.me }
        receiver.pin = settings.pin
        receiver.trusted = settings.trusted
        receiver.registered = { [weak self] in self?.add($0) }
    }

    public var settings: ShareSettings {
        get { lock.withLock { _settings } }
        set {
            lock.withLock { _settings = newValue }
            receiver.folder = newValue.folder
            receiver.pin = newValue.pin
            receiver.trusted = newValue.trusted
        }
    }

    public var me: DeviceInfo {
        let settings = settings
        return DeviceInfo(alias: settings.alias, deviceModel: "macOS", deviceType: "desktop", fingerprint: settings.fingerprint,
                          port: settings.port, protocol: "http")
    }

    /// The devices around, as last heard from.
    public var list: [Peer] {
        lock.withLock { peers.values.map(\.peer) }.sorted { $0.info.alias.localizedCaseInsensitiveCompare($1.info.alias) == .orderedAscending }
    }

    /// Starts receiving and (with `discover`) finding devices. `ready` gets nil, or why the server couldn't start.
    public func start(discover: Bool = true, ready: @escaping @Sendable (Error?) -> Void) {
        do {
            let server = try HTTPServer(port: settings.port) { [receiver] in await receiver.handle($0) }
            self.server = server
            server.start { [weak self] error in
                ready(error)
                guard error == nil, discover, let self else { return }
                let discovery = Discovery(me: { [unowned self] in self.me }) { [sender] address, port, scheme in
                    await sender.register(address: address, port: port, protocol: scheme)
                }
                discovery.found = { [weak self] in self?.add($0) }
                discovery.start()
                discovery.announce()
                self.discovery = discovery
            }
        } catch {
            ready(error)
        }
    }

    /// Looks for devices again: an announcement, then (if asked) every address of the local networks.
    public func refresh(scan: Bool = true) async {
        lock.withLock {
            peers = peers.filter { Date().timeIntervalSince($0.value.seen) < 120 }
        }
        discovery?.announce()
        if scan { await discovery?.scan(port: ShareProtocol.port) }
        peersChanged()
    }

    /// A device at `address`, asked directly (typed in).
    public func connect(_ address: String, port: Int = ShareProtocol.port) async -> Peer? {
        let peer: Peer?
        if let found = await sender.register(address: address, port: port, protocol: "https", timeout: 4) {
            peer = found
        } else {
            peer = await sender.register(address: address, port: port, protocol: "http", timeout: 4)
        }
        if let peer { add(peer) }
        return peer
    }

    private func add(_ peer: Peer) {
        if peer.info.fingerprint == settings.fingerprint { return }
        lock.withLock { peers[peer.id] = (peer, Date()) }
        peersChanged()
    }

    public func send(to peer: Peer, items: [Outgoing], pin: String? = nil,
                     progress: @escaping @Sendable (Int64, Int64) -> Void) async -> SendResult {
        await sender.send(to: peer, items: items, pin: pin, progress: progress)
    }

    public func stop() {
        discovery?.stop()
        discovery = nil
        server?.stop()
        server = nil
        receiver.cancel()
    }
}
