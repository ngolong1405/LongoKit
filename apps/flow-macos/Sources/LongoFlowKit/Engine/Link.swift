import CryptoKit
import Foundation
import Network

/// A connection to another Mac: messages framed by their length, in the clear for pairing and the hello, then each one
/// sealed. Sending is safe from any thread; messages arrive on the link's own queue, in order.
final class Link: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var buffer = Data()
    private var sending: Cipher?
    private var receiving: Cipher?
    private var closed = false

    /// A message came in.
    var received: (Message) -> Void = { _ in }
    /// The link is gone (the other side left, the network dropped, or a message didn't open).
    var ended: () -> Void = {}

    /// Messages aren't held back to fill packets: a pointer move goes out at once.
    static var parameters: NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2
        tcp.keepaliveInterval = 1
        tcp.keepaliveCount = 3
        tcp.connectionTimeout = 4
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = false
        // Wi-Fi sends these first, as it does a call's voice.
        parameters.serviceClass = .interactiveVoice
        return parameters
    }

    init(_ connection: NWConnection) {
        self.connection = connection
        queue = DispatchQueue(label: "LongoFlow.link", qos: .userInteractive)
    }

    convenience init(to endpoint: NWEndpoint) {
        self.init(NWConnection(to: endpoint, using: Self.parameters))
    }

    /// Starts it; `ready` once it's connected (or not).
    func start(ready: @escaping (Bool) -> Void = { _ in }) {
        var reported = false
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if !reported { reported = true; ready(true) }
                self?.read()
            case .failed, .cancelled:
                if !reported { reported = true; ready(false) }
                self?.end()
            case .waiting:
                // No route (the other Mac went to sleep): give up rather than wait.
                if !reported { reported = true; ready(false) }
                self?.end()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    /// From now on, messages are sealed both ways. The dialer and the listener use different nonce prefixes.
    func encrypt(key: SymmetricKeyData, dialer: Bool) {
        lock.lock()
        sending = Cipher(key: key.key, direction: dialer ? 1 : 2)
        receiving = Cipher(key: key.key, direction: dialer ? 2 : 1)
        lock.unlock()
    }

    func send(_ message: Message) {
        send(message) { }
    }

    private func send(_ message: Message, then done: @escaping () -> Void) {
        lock.lock()
        let body: Data?
        if sending != nil { body = sending!.seal(message.bytes) } else { body = message.bytes }
        lock.unlock()
        guard let body else { return }
        var frame = Data(count: 4)
        let length = UInt32(body.count).bigEndian
        withUnsafeBytes(of: length) { frame.replaceSubrange(0..<4, with: $0) }
        frame.append(body)
        connection.send(content: frame, completion: .contentProcessed { _ in done() })
    }

    // MARK: - Big messages

    private static let chunkSize = 32 << 10
    private var bulk: [Message] = []
    private var pumping = false
    private var nextBulk: UInt32 = 0
    private var arriving: [UInt32: Data] = [:]

    /// Sends a big message in pieces, one at a time: the pointer's messages go in between, so a picture on the
    /// clipboard never holds the mouse up for more than one piece.
    func sendBulk(_ message: Message) {
        let bytes = message.bytes
        lock.lock()
        let id = nextBulk
        nextBulk &+= 1
        var at = 0
        repeat {
            let piece = bytes[at..<min(at + Self.chunkSize, bytes.count)]
            var writer = Writer()
            writer.u64(UInt64(id) << 32 | UInt64(bytes.count))
            writer.u64(UInt64(at))
            writer.data.append(piece)
            bulk.append(Message(.chunk, writer.data))
            at += Self.chunkSize
        } while at < bytes.count
        let start = !pumping
        pumping = true
        lock.unlock()
        if start { pump() }
    }

    /// The next piece, once the last one is on its way.
    private func pump() {
        lock.lock()
        guard !bulk.isEmpty, !closed else {
            pumping = false
            lock.unlock()
            return
        }
        let piece = bulk.removeFirst()
        lock.unlock()
        send(piece) { [weak self] in self?.queue.async { self?.pump() } }
    }

    /// A piece in; the whole message once its last piece is.
    private func arrived(_ piece: Message) -> Message? {
        var reader = Reader(piece.payload)
        guard let head = reader.u64(), let at = reader.u64() else { return nil }
        let id = UInt32(head >> 32), total = Int(head & 0xFFFF_FFFF)
        guard total <= 64 << 20 else { return nil }
        let data = reader.rest
        var whole = arriving[id] ?? Data()
        guard Int(at) == whole.count else {
            arriving[id] = nil
            return nil
        }
        whole.append(data)
        if whole.count >= total {
            arriving[id] = nil
            return Message(bytes: whole)
        }
        arriving[id] = whole
        return nil
    }

    private func read() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drain()
            }
            if error != nil || complete { self.end() } else if !self.closed { self.read() }
        }
    }

    private func drain() {
        while buffer.count >= 4 {
            let length = Int(buffer.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
            // Clipboard pictures are the biggest messages; anything past this is a broken link.
            guard length <= 64 << 20 else { return end() }
            guard buffer.count >= 4 + length else { return }
            let body = Data(buffer.dropFirst(4).prefix(length))
            buffer.removeFirst(4 + length)
            lock.lock()
            let plain: Data?
            if receiving != nil { plain = receiving!.open(body) } else { plain = body }
            lock.unlock()
            guard let plain, let message = Message(bytes: plain) else { return end() }
            if message.kind == .chunk {
                if let whole = arrived(message) { received(whole) }
            } else {
                received(message)
            }
        }
    }

    private func end() {
        lock.lock()
        let first = !closed
        closed = true
        lock.unlock()
        guard first else { return }
        connection.cancel()
        ended()
    }

    func close() { end() }

    var remote: NWEndpoint { connection.endpoint }
}

/// A session key, kept as bytes so a link can be told it from another thread.
struct SymmetricKeyData: @unchecked Sendable {
    let key: CryptoKit.SymmetricKey
}
