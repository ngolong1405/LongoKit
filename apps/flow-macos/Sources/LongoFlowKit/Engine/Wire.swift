import CryptoKit
import Foundation

/// Where another Mac sits, seen from this one.
public enum Side: UInt8, Codable, CaseIterable, Sendable {
    case left, right, top, bottom

    public var opposite: Side {
        switch self {
        case .left: return .right
        case .right: return .left
        case .top: return .bottom
        case .bottom: return .top
        }
    }
}

/// What goes over a link. Pairing and the hello are JSON in the clear; everything after is binary, encrypted.
enum Kind: UInt8 {
    case hello = 1, pairRequest, pairChallenge, pairConfirm, pairResult
    /// The pointer crossed onto the receiver: where, in the receiver's own coordinates.
    case enter
    /// The pointer left the receiver back to the sender: where, in the sender's coordinates.
    case leave
    case move, button, scroll, key, flags
    case clipboard
    /// Where the sender's screens sit in the receiver's coordinates (the receiver's arrangement of the two).
    case layout
    /// The controller takes its keyboard and mouse back (Esc three times, or it lost track).
    case release
    case ping
    /// The sender's displays, in its own global coordinates.
    case screens
}

struct Hello: Codable {
    var id: String
    var name: String
    var nonce: Data
}

struct PairRequest: Codable {
    var id: String
    var name: String
    var salt: Data
}

struct PairChallenge: Codable {
    var id: String
    var name: String
    var salt: Data
}

/// The link's key, and where the requester puts the other Mac, sealed with the key the code makes.
struct PairConfirm: Codable {
    var box: Data
}

struct PairSecret: Codable {
    var key: Data
    /// Where the requester has the other Mac.
    var side: Side
}

struct PairResult: Codable {
    var ok: Bool
    var box: Data?
}

/// A message: its kind and its bytes.
struct Message {
    var kind: Kind
    var payload: Data

    init(_ kind: Kind, _ payload: Data = Data()) {
        self.kind = kind
        self.payload = payload
    }

    static func json<T: Encodable>(_ kind: Kind, _ value: T) -> Message {
        Message(kind, (try? JSONEncoder().encode(value)) ?? Data())
    }

    func decode<T: Decodable>(_ type: T.Type) -> T? {
        try? JSONDecoder().decode(type, from: payload)
    }

    var bytes: Data {
        var data = Data([kind.rawValue])
        data.append(payload)
        return data
    }

    init?(bytes: Data) {
        guard let first = bytes.first, let kind = Kind(rawValue: first) else { return nil }
        self.kind = kind
        payload = Data(bytes.dropFirst())
    }
}

/// Little-endian numbers in and out of a payload.
struct Writer {
    var data = Data()

    mutating func u8(_ value: UInt8) { data.append(value) }
    mutating func u16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    mutating func u64(_ value: UInt64) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    mutating func f32(_ value: Float) { withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
    mutating func point(_ value: CGPoint) {
        f32(Float(value.x))
        f32(Float(value.y))
    }
}

struct Reader {
    private let data: Data
    private var at: Int

    init(_ data: Data) {
        self.data = data
        at = data.startIndex
    }

    private mutating func take(_ count: Int) -> Data? {
        guard at + count <= data.endIndex else { return nil }
        defer { at += count }
        return data[at..<at + count]
    }

    private func number<T: FixedWidthInteger>(_ bytes: Data?) -> T? {
        guard let bytes else { return nil }
        var value: T = 0
        withUnsafeMutableBytes(of: &value) { $0.copyBytes(from: bytes) }
        return T(littleEndian: value)
    }

    mutating func u8() -> UInt8? { take(1)?.first }
    mutating func u16() -> UInt16? { number(take(2)) }
    mutating func u64() -> UInt64? { number(take(8)) }
    mutating func f32() -> Float? { (number(take(4)) as UInt32?).map(Float.init(bitPattern:)) }
    mutating func point() -> CGPoint? {
        guard let x = f32(), let y = f32() else { return nil }
        return CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
    var rest: Data { data[at...] }
}

/// The keys: a link key from the pairing code, and a fresh session key each time two paired Macs connect.
enum Keys {
    /// Six digits, shown on the Mac being asked.
    static func code() -> String {
        String(format: "%06d", Int.random(in: 0...999_999))
    }

    static func random(_ count: Int = 32) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }

    /// The key the pairing code makes, for sealing the link key on its way over.
    static func fromCode(_ code: String, requester: Data, answerer: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(code.utf8)), salt: requester + answerer,
                               info: Data("longoflow pairing".utf8), outputByteCount: 32)
    }

    static func session(_ link: Data, dialer: Data, listener: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: link), salt: dialer + listener,
                               info: Data("longoflow session".utf8), outputByteCount: 32)
    }

    static func seal(_ data: Data, _ key: SymmetricKey) -> Data? {
        try? ChaChaPoly.seal(data, using: key).combined
    }

    static func open(_ data: Data, _ key: SymmetricKey) -> Data? {
        guard let box = try? ChaChaPoly.SealedBox(combined: data) else { return nil }
        return try? ChaChaPoly.open(box, using: key)
    }
}

/// One direction of an encrypted link: each message sealed with the session key and the next counter as nonce, so a
/// message can't be replayed or reordered.
struct Cipher {
    let key: SymmetricKey
    let direction: UInt8
    private var counter: UInt64 = 0

    init(key: SymmetricKey, direction: UInt8) {
        self.key = key
        self.direction = direction
    }

    private mutating func nonce() -> ChaChaPoly.Nonce {
        var bytes = [UInt8](repeating: 0, count: 12)
        bytes[0] = direction
        withUnsafeBytes(of: counter.bigEndian) { for (index, byte) in $0.enumerated() { bytes[4 + index] = byte } }
        counter += 1
        return try! ChaChaPoly.Nonce(data: bytes)
    }

    mutating func seal(_ data: Data) -> Data? {
        guard let box = try? ChaChaPoly.seal(data, using: key, nonce: nonce()) else { return nil }
        return box.ciphertext + box.tag
    }

    mutating func open(_ data: Data) -> Data? {
        guard data.count >= 16 else { return nil }
        let nonce = nonce()
        guard let box = try? ChaChaPoly.SealedBox(nonce: nonce, ciphertext: data.dropLast(16), tag: data.suffix(16)) else { return nil }
        return try? ChaChaPoly.open(box, using: key)
    }
}
