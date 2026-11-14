import CryptoKit
import Foundation
import Network

/// A Mac paired with this one: its link key, and where it sits.
public struct PairedMac: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var key: Data
    /// Where it was put when paired, until its screens are known and placed.
    public var side: Side
    /// Its displays, in its own coordinates (as it last said).
    public var screens: [CGRect] = []
    /// Which of them is a laptop's own display, if one is.
    public var builtin: Int?
    /// Their names, short, as it said.
    public var names: [String] = []
    /// Where its coordinates sit in this Mac's: its point + offset = here. Nil until it's placed.
    public var offset: CGPoint?

    public init(id: String, name: String, key: Data, side: Side, screens: [CGRect] = [], offset: CGPoint? = nil) {
        self.id = id
        self.name = name
        self.key = key
        self.side = side
        self.screens = screens
        self.offset = offset
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        key = try c.decode(Data.self, forKey: .key)
        side = try c.decodeIfPresent(Side.self, forKey: .side) ?? .right
        screens = try c.decodeIfPresent([CGRect].self, forKey: .screens) ?? []
        offset = try c.decodeIfPresent(CGPoint.self, forKey: .offset)
        builtin = try c.decodeIfPresent(Int.self, forKey: .builtin)
        names = try c.decodeIfPresent([String].self, forKey: .names) ?? []
    }

    /// Its screens, or a laptop's when it hasn't said yet.
    public var knownScreens: [CGRect] { screens.isEmpty ? [CGRect(x: 0, y: 0, width: 1512, height: 982)] : screens }

    /// Where it sits by default: on `side` of these screens, its main display's edge against theirs, centred.
    public func placed(next local: [CGRect]) -> CGPoint {
        let union = local.reduce(CGRect.null) { $0.union($1) }
        let theirs = knownScreens.reduce(CGRect.null) { $0.union($1) }
        switch side {
        case .right: return CGPoint(x: union.maxX - theirs.minX, y: union.midY - theirs.midY)
        case .left: return CGPoint(x: union.minX - theirs.maxX, y: union.midY - theirs.midY)
        case .top: return CGPoint(x: union.midX - theirs.midX, y: union.minY - theirs.maxY)
        case .bottom: return CGPoint(x: union.midX - theirs.midX, y: union.maxY - theirs.minY)
        }
    }
}

/// A Mac with Longo Flow seen on the network.
public struct NearbyMac: Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    let endpoint: NWEndpoint
}

/// This Mac on the network: it shows itself over Bonjour, finds the others, pairs with a six-digit code, and keeps an
/// encrypted link to each paired Mac that's around. Of two paired Macs, the one with the smaller id dials.
/// Callbacks come on the node's queue.
final class FlowNode: @unchecked Sendable {
    static let serviceType = "_longoflow._tcp"

    let id: String
    private(set) var name: String
    private let queue = DispatchQueue(label: "LongoFlow.node")
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var nearby: [String: NearbyMac] = [:]
    private var paired: [String: PairedMac]
    private var links: [String: Link] = [:] {
        didSet {
            linksLock.lock()
            live = links
            linksLock.unlock()
        }
    }
    /// The links, for sending from any thread (the event tap's) without waiting on the node's queue.
    private let linksLock = NSLock()
    private var live: [String: Link] = [:]
    private var dialing: Set<String> = []
    /// Links being set up (dialed, or in and not yet a pairing or a session), kept alive until they are or end.
    private var holding: [ObjectIdentifier: Link] = [:]
    private var retry: DispatchSourceTimer?

    /// Asking another Mac: its link, the salts, where it's to sit.
    private var asking: (id: String, name: String, link: Link, mine: Data, theirs: Data?, side: Side)?
    /// Asked by another Mac: the code shown here, its request.
    private var asked: (link: Link, code: String, request: PairRequest, mine: Data)?

    var nearbyChanged: ([NearbyMac]) -> Void = { _ in }
    /// Paired Macs changed (one added, removed, moved).
    var pairedChanged: ([PairedMac]) -> Void = { _ in }
    var connectedChanged: (Set<String>) -> Void = { _ in }
    /// Another Mac asks to pair: show this code (nil when it's over).
    var showCode: (_ code: String?, _ from: String) -> Void = { _, _ in }
    /// The Mac asked answered: type the code it shows.
    var needsCode: (_ from: String) -> Void = { _ in }
    /// The code typed was wrong: the other Mac shows a new one to type.
    var codeRejected: (_ from: String) -> Void = { _ in }
    /// Pairing ended: paired, or not (cancelled, or the other Mac went away).
    var pairingEnded: (_ name: String, _ ok: Bool) -> Void = { _, _ in }
    /// A Mac took the arrangement this one sent.
    var placedThere: (_ mac: String) -> Void = { _ in }
    /// A message from a paired, connected Mac.
    var received: (_ from: String, _ message: Message) -> Void = { _, _ in }

    init(id: String, name: String, paired: [PairedMac]) {
        self.id = id
        self.name = name
        self.paired = Dictionary(uniqueKeysWithValues: paired.map { ($0.id, $0) })
    }

    // MARK: - Starting

    /// Listens (on `port`, any when 0), shows itself and looks for others over Bonjour (off in tests).
    func start(port: UInt16 = 0, bonjour: Bool = true, ready: @escaping (UInt16?) -> Void = { _ in }) {
        queue.async { [self] in
            guard let listener = try? NWListener(using: Link.parameters, on: port == 0 ? .any : NWEndpoint.Port(rawValue: port)!) else {
                ready(nil)
                return
            }
            if bonjour {
                listener.service = NWListener.Service(name: name, type: Self.serviceType, domain: nil,
                                                      txtRecord: NWTXTRecord(["id": id, "name": name]))
            }
            listener.newConnectionHandler = { [weak self] connection in self?.incoming(Link(connection)) }
            var reported = false
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready where !reported:
                    reported = true
                    ready(listener.port?.rawValue)
                case .failed where !reported:
                    reported = true
                    ready(nil)
                default: break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
            if bonjour { browse() }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 3, repeating: 3)
            timer.setEventHandler { [weak self] in self?.connectAll() }
            timer.resume()
            retry = timer
        }
    }

    func stop() {
        queue.sync {
            retry?.cancel()
            retry = nil
            browser?.cancel()
            browser = nil
            listener?.cancel()
            listener = nil
            for link in links.values { link.close() }
            links = [:]
            asking?.link.close()
            asked?.link.close()
        }
    }

    private func browse() {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            var found: [String: NearbyMac] = [:]
            for result in results {
                guard case .bonjour(let txt) = result.metadata, let id = txt["id"], id != self.id else { continue }
                found[id] = NearbyMac(id: id, name: txt["name"] ?? id, endpoint: result.endpoint)
            }
            self.nearby = found
            self.nearbyChanged(Array(found.values).sorted { $0.name < $1.name })
            self.connectAll()
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    /// For tests (and typing an address): a Mac at a known place.
    func add(_ nearby: NearbyMac) {
        queue.async { [self] in
            self.nearby[nearby.id] = nearby
            nearbyChanged(Array(self.nearby.values))
            connectAll()
        }
    }

    // MARK: - Pairing

    /// Asks `mac` to pair; it shows a code to type here. `side` is where it sits from here.
    func pair(with mac: String, side: Side) {
        queue.async { [self] in
            guard let found = nearby[mac] else { return pairingEnded("", false) }
            asking?.link.close()
            let link = Link(to: found.endpoint)
            let salt = Keys.random(16)
            asking = (found.id, found.name, link, salt, nil, side)
            link.received = { [weak self, weak link] message in
                guard let self, let link else { return }
                self.queue.async { self.asking(link, message) }
            }
            link.ended = { [weak self, weak link] in
                self?.queue.async {
                    guard let self, let link, self.asking?.link === link else { return }
                    self.asking = nil
                    self.pairingEnded(found.name, false)
                }
            }
            link.start { [weak link] ok in
                guard ok, let link else { return }
                link.send(.json(.pairRequest, PairRequest(id: self.id, name: self.name, salt: salt)))
            }
        }
    }

    /// The code the other Mac shows.
    func submit(code: String) {
        queue.async { [self] in
            guard let pending = asking, let theirs = pending.theirs else { return }
            let key = Keys.fromCode(code.trimmingCharacters(in: .whitespaces), requester: pending.mine, answerer: theirs)
            let secret = Keys.random(32)
            guard let plain = try? JSONEncoder().encode(PairSecret(key: secret, side: pending.side)),
                  let box = Keys.seal(plain, key) else { return }
            pendingSecret = (secret, key)
            pending.link.send(.json(.pairConfirm, PairConfirm(box: box)))
        }
    }

    private var pendingSecret: (secret: Data, key: SymmetricKey)?

    func cancelPairing() {
        queue.async { [self] in
            let cancelled = asking
            asking = nil
            cancelled?.link.close()
            if let cancelled { pairingEnded(cancelled.name, false) }
            asked?.link.close()
            asked = nil
            showCode(nil, "")
        }
    }

    /// Messages on a link this Mac opened to pair.
    private func asking(_ link: Link, _ message: Message) {
        guard let pending = asking, pending.link === link else { return }
        switch message.kind {
        case .pairChallenge:
            guard let challenge = message.decode(PairChallenge.self) else { return }
            asking = (pending.id, challenge.name, link, pending.mine, challenge.salt, pending.side)
            needsCode(challenge.name)
        case .pairResult:
            let result = message.decode(PairResult.self)
            guard let secret = pendingSecret, result?.ok == true, let box = result?.box,
                  Keys.open(box, secret.key) == Data("ok".utf8) else {
                // A wrong code: the other Mac shows a new one to try again.
                pendingSecret = nil
                codeRejected(pending.name)
                return
            }
            let mac = PairedMac(id: pending.id, name: pending.name, key: secret.secret, side: pending.side)
            paired[mac.id] = mac
            asking = nil
            pendingSecret = nil
            link.close()
            pairedChanged(Array(paired.values))
            pairingEnded(mac.name, true)
            connectAll()
        default:
            break
        }
    }

    /// Messages on a link another Mac opened to pair with this one.
    private func asked(_ link: Link, _ message: Message) {
        switch message.kind {
        case .pairRequest:
            guard let request = message.decode(PairRequest.self) else { return link.close() }
            asked?.link.close()
            let code = Keys.code()
            let salt = Keys.random(16)
            asked = (link, code, request, salt)
            link.send(.json(.pairChallenge, PairChallenge(id: id, name: name, salt: salt)))
            showCode(code, request.name)
        case .pairConfirm:
            guard let pending = asked, pending.link === link else { return }
            let key = Keys.fromCode(pending.code, requester: pending.request.salt, answerer: pending.mine)
            guard let confirm = message.decode(PairConfirm.self), let plain = Keys.open(confirm.box, key),
                  let secret = try? JSONDecoder().decode(PairSecret.self, from: plain) else {
                // Wrong code: a new one, so codes can't be tried one after another on the same one.
                link.send(.json(.pairResult, PairResult(ok: false, box: nil)))
                let code = Keys.code()
                asked = (link, code, pending.request, pending.mine)
                showCode(code, pending.request.name)
                return
            }
            let mac = PairedMac(id: pending.request.id, name: pending.request.name, key: secret.key, side: secret.side.opposite)
            paired[mac.id] = mac
            link.send(.json(.pairResult, PairResult(ok: true, box: Keys.seal(Data("ok".utf8), key))))
            asked = nil
            showCode(nil, mac.name)
            pairedChanged(Array(paired.values))
            pairingEnded(mac.name, true)
        default:
            break
        }
    }

    func unpair(_ mac: String) {
        queue.async { [self] in
            paired[mac] = nil
            links.removeValue(forKey: mac)?.close()
            pairedChanged(Array(paired.values))
            connectedChanged(Set(links.keys))
        }
    }

    /// This Mac's displays, for telling the others (set by the app; read on the node's queue).
    var localScreens: () -> [CGRect] = { [] }
    /// Their wallpapers, small (set by the app, which reads them on the main thread).
    var localWallpapers: [Data?] = []
    /// Their names, short (set by the app, which reads them on the main thread).
    var localNames: [String] = []

    /// Puts a paired Mac's screens at `offset` in this Mac's coordinates, here and there (there, the inverse).
    func place(_ mac: String, at offset: CGPoint) {
        queue.async { [self] in
            guard paired[mac] != nil else { return }
            paired[mac]!.offset = offset
            pairedChanged(Array(paired.values))
            var writer = Writer()
            writer.point(CGPoint(x: -offset.x, y: -offset.y))
            links[mac]?.send(Message(.layout, writer.data))
        }
    }

    /// Tells every connected Mac this one's displays (at the start, and when they change).
    func sendScreens() {
        queue.async { [self] in
            for mac in links.keys { sendScreens(to: mac) }
        }
    }

    private func sendScreens(to mac: String) {
        let screens = localScreens()
        var writer = Writer()
        writer.u8(UInt8(min(screens.count, 255)))
        for screen in screens.prefix(255) {
            writer.point(screen.origin)
            writer.point(CGPoint(x: screen.width, y: screen.height))
        }
        // After the displays (earlier versions stop reading before it): the laptop's own, or 255.
        writer.u8(UInt8(clamping: Screens.builtin(in: screens) ?? 255))
        // Then each display's name, short (also past what earlier versions read).
        for index in screens.indices.prefix(255) {
            let name = Data((localNames.indices.contains(index) ? localNames[index] : "").utf8.prefix(60))
            writer.u8(UInt8(name.count))
            writer.data.append(name)
        }
        links[mac]?.send(Message(.screens, writer.data))
        for (index, picture) in localWallpapers.enumerated() {
            guard let picture else { continue }
            links[mac]?.sendBulk(Message(.wallpaper, Data([UInt8(clamping: index)]) + picture))
        }
    }

    // MARK: - Sessions

    /// Dials each paired Mac that's around and not linked yet (when this Mac's id is the smaller).
    private func connectAll() {
        for mac in paired.values where links[mac.id] == nil && !dialing.contains(mac.id) && id < mac.id {
            guard let found = nearby[mac.id] else { continue }
            dial(mac, found.endpoint)
        }
    }

    private func dial(_ mac: PairedMac, _ endpoint: NWEndpoint) {
        dialing.insert(mac.id)
        let link = Link(to: endpoint)
        holding[ObjectIdentifier(link)] = link
        let nonce = Keys.random(16)
        link.received = { [weak self, weak link] message in
            guard let self, let link else { return }
            // The pointer and keys go straight on, from the link's own queue: no wait behind anything else here.
            if Self.isInput(message.kind) { return self.input(mac.id, message) }
            self.queue.async {
                if message.kind == .hello, let hello = message.decode(Hello.self), hello.id == mac.id, let current = self.paired[mac.id] {
                    link.encrypt(key: SymmetricKeyData(key: Keys.session(current.key, dialer: nonce, listener: hello.nonce)), dialer: true)
                    link.send(Message(.ping))
                } else if message.kind == .ping {
                    self.linked(mac.id, link)
                } else {
                    self.deliver(mac.id, message)
                }
            }
        }
        link.ended = { [weak self, weak link] in
            self?.queue.async {
                guard let self else { return }
                self.dialing.remove(mac.id)
                if let link {
                    self.holding[ObjectIdentifier(link)] = nil
                    if self.links[mac.id] === link { self.unlinked(mac.id) }
                }
            }
        }
        link.start { [weak self, weak link] ok in
            guard let self, let link else { return }
            if ok { link.send(.json(.hello, Hello(id: self.id, name: self.name, nonce: nonce))) }
        }
    }

    /// A connection in: pairing, or a paired Mac's hello.
    private func incoming(_ link: Link) {
        queue.async { self.holding[ObjectIdentifier(link)] = link }
        var macId: String?
        link.received = { [weak self, weak link] message in
            guard let self, let link else { return }
            if Self.isInput(message.kind), let mac = macId { return self.input(mac, message) }
            self.queue.async {
                if let mac = macId {
                    if message.kind == .ping {
                        link.send(Message(.ping))
                        self.linked(mac, link)
                    } else {
                        self.deliver(mac, message)
                    }
                    return
                }
                switch message.kind {
                case .hello:
                    guard let hello = message.decode(Hello.self), let mac = self.paired[hello.id] else { return link.close() }
                    let mine = Keys.random(16)
                    macId = mac.id
                    link.send(.json(.hello, Hello(id: self.id, name: self.name, nonce: mine)))
                    link.encrypt(key: SymmetricKeyData(key: Keys.session(mac.key, dialer: hello.nonce, listener: mine)), dialer: false)
                case .pairRequest, .pairConfirm:
                    self.asked(link, message)
                default:
                    link.close()
                }
            }
        }
        link.ended = { [weak self, weak link] in
            self?.queue.async {
                guard let self else { return }
                if let link { self.holding[ObjectIdentifier(link)] = nil }
                if let mac = macId, let link, self.links[mac] === link { self.unlinked(mac) }
                if let link, self.asked?.link === link {
                    self.asked = nil
                    self.showCode(nil, "")
                }
            }
        }
        link.start()
    }

    private func linked(_ mac: String, _ link: Link) {
        guard links[mac] !== link else { return }
        links[mac]?.close()
        links[mac] = link
        dialing.remove(mac)
        connectedChanged(Set(links.keys))
        sendScreens(to: mac)
    }

    private func unlinked(_ mac: String) {
        links[mac] = nil
        connectedChanged(Set(links.keys))
    }

    private func deliver(_ mac: String, _ message: Message) {
        var reader = Reader(message.payload)
        switch message.kind {
        case .layout:
            guard let offset = reader.point(), paired[mac] != nil else { return }
            paired[mac]!.offset = offset
            pairedChanged(Array(paired.values))
            links[mac]?.send(Message(.placed))
            return
        case .placed:
            placedThere(mac)
            return
        case .screens:
            guard let count = reader.u8(), paired[mac] != nil else { return }
            var screens: [CGRect] = []
            for _ in 0..<count {
                guard let origin = reader.point(), let size = reader.point() else { break }
                screens.append(CGRect(origin: origin, size: CGSize(width: size.x, height: size.y)))
            }
            paired[mac]!.screens = screens
            if let index = reader.u8() { paired[mac]!.builtin = index == 255 ? nil : Int(index) }
            var names: [String] = []
            for _ in screens.indices {
                guard let length = reader.u8(), let bytes = reader.bytes(Int(length)) else { break }
                names.append(String(decoding: bytes, as: UTF8.self))
            }
            paired[mac]!.names = names
            // Not placed yet: the Mac with the smaller id places the two, from the side chosen when pairing.
            if paired[mac]!.offset == nil && id < mac {
                let offset = paired[mac]!.placed(next: localScreens())
                paired[mac]!.offset = offset
                var writer = Writer()
                writer.point(CGPoint(x: -offset.x, y: -offset.y))
                links[mac]?.send(Message(.layout, writer.data))
            }
            pairedChanged(Array(paired.values))
            return
        default:
            break
        }
        received(mac, message)
    }

    /// The pointer's, the keyboard's, and the keep-awake: handled as they come.
    private static func isInput(_ kind: Kind) -> Bool {
        switch kind {
        case .enter, .leave, .move, .button, .scroll, .key, .flags, .release, .awake: return true
        default: return false
        }
    }

    private func input(_ mac: String, _ message: Message) {
        if message.kind != .awake { received(mac, message) }
    }

    /// Sends a big message (a clipboard picture) to a connected Mac, in pieces between the pointer's.
    func sendBulk(_ message: Message, to mac: String) {
        linksLock.lock()
        let link = live[mac]
        linksLock.unlock()
        link?.sendBulk(message)
    }

    /// Sends to a connected Mac (any thread; nothing when it isn't connected).
    func send(_ message: Message, to mac: String) {
        linksLock.lock()
        let link = live[mac]
        linksLock.unlock()
        link?.send(message)
    }

    /// The paired Macs, now (waits for the node's queue: not from its callbacks).
    var pairedMacs: [PairedMac] { queue.sync { Array(paired.values) } }

    var connected: Set<String> {
        linksLock.lock()
        defer { linksLock.unlock() }
        return Set(live.keys)
    }
}
