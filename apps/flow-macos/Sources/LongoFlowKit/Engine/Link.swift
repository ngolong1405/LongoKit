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
        lock.lock()
        let body: Data?
        if sending != nil { body = sending!.seal(message.bytes) } else { body = message.bytes }
        lock.unlock()
        guard let body else { return }
        var frame = Data(count: 4)
        let length = UInt32(body.count).bigEndian
        withUnsafeBytes(of: length) { frame.replaceSubrange(0..<4, with: $0) }
        frame.append(body)
        connection.send(content: frame, completion: .contentProcessed { _ in })
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
            received(message)
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
