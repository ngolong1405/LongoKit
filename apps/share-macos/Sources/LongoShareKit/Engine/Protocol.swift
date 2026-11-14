import Foundation

/// LocalSend's protocol, version 2: the port, the multicast group and the HTTP paths.
/// https://github.com/localsend/protocol
public enum ShareProtocol {
    public static let version = "2.1"
    public static let port = 53317
    public static let multicastAddress = "224.0.0.167"
    static let base = "/api/localsend/v2"
    static let register = base + "/register"
    static let info = base + "/info"
    static let prepareUpload = base + "/prepare-upload"
    static let upload = base + "/upload"
    static let cancel = base + "/cancel"

    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
}

/// A device, as it tells others about itself (announcements, /register, /info, prepare-upload).
public struct DeviceInfo: Codable, Hashable, Sendable {
    public var alias: String
    public var version: String = ShareProtocol.version
    public var deviceModel: String?
    /// mobile, desktop, web, headless, server.
    public var deviceType: String? = "desktop"
    public var fingerprint: String
    public var port: Int = ShareProtocol.port
    /// http or https.
    public var `protocol`: String = "http"
    public var download: Bool? = false
    /// Set in multicast messages: true asks others to answer.
    public var announce: Bool?

    public init(alias: String, deviceModel: String? = nil, deviceType: String? = "desktop", fingerprint: String,
                port: Int = ShareProtocol.port, protocol: String = "http", announce: Bool? = nil) {
        self.alias = alias
        self.deviceModel = deviceModel
        self.deviceType = deviceType
        self.fingerprint = fingerprint
        self.port = port
        self.protocol = `protocol`
        self.announce = announce
    }

    // Lenient: /info and older versions leave fields out.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alias = try c.decodeIfPresent(String.self, forKey: .alias) ?? "?"
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? "1.0"
        deviceModel = try c.decodeIfPresent(String.self, forKey: .deviceModel)
        deviceType = try c.decodeIfPresent(String.self, forKey: .deviceType)
        fingerprint = try c.decodeIfPresent(String.self, forKey: .fingerprint) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? ShareProtocol.port
        `protocol` = try c.decodeIfPresent(String.self, forKey: .protocol) ?? "https"
        download = try c.decodeIfPresent(Bool.self, forKey: .download)
        announce = try c.decodeIfPresent(Bool.self, forKey: .announce)
            ?? c.decodeIfPresent(Bool.self, forKey: .announcement)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(alias, forKey: .alias)
        try c.encode(version, forKey: .version)
        try c.encodeIfPresent(deviceModel, forKey: .deviceModel)
        try c.encodeIfPresent(deviceType, forKey: .deviceType)
        try c.encode(fingerprint, forKey: .fingerprint)
        try c.encode(port, forKey: .port)
        try c.encode(`protocol`, forKey: .protocol)
        try c.encodeIfPresent(download, forKey: .download)
        try c.encodeIfPresent(announce, forKey: .announce)
    }

    private enum CodingKeys: String, CodingKey {
        case alias, version, deviceModel, deviceType, fingerprint, port, `protocol`, download, announce, announcement
    }
}

public struct FileMetadata: Codable, Hashable, Sendable {
    public var modified: String?
    public var accessed: String?
}

/// A file offered in prepare-upload.
public struct ShareFile: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var fileName: String
    public var size: Int64
    public var fileType: String
    public var sha256: String?
    /// A message's text (sent as a text file with nothing to upload).
    public var preview: String?
    public var metadata: FileMetadata?

    public init(id: String, fileName: String, size: Int64, fileType: String, sha256: String? = nil, preview: String? = nil,
                metadata: FileMetadata? = nil) {
        self.id = id
        self.fileName = fileName
        self.size = size
        self.fileType = fileType
        self.sha256 = sha256
        self.preview = preview
        self.metadata = metadata
    }
}

struct PrepareUploadRequest: Codable {
    var info: DeviceInfo
    var files: [String: ShareFile]
}

struct PrepareUploadResponse: Codable {
    var sessionId: String
    var files: [String: String]
}

/// A device on the network: what it said about itself, and where it was heard from.
public struct Peer: Hashable, Sendable, Identifiable {
    public var info: DeviceInfo
    public var address: String

    public init(info: DeviceInfo, address: String) {
        self.info = info
        self.address = address
    }

    public var id: String { info.fingerprint.isEmpty ? address : info.fingerprint }

    /// One of its API's paths.
    func url(_ path: String) -> URL {
        let host = address.contains(":") ? "[\(address)]" : address
        return URL(string: "\(info.protocol)://\(host):\(info.port)\(path)")!
    }
}

/// Files someone wants to send, waiting for an answer.
public struct IncomingTransfer: Sendable {
    public var from: Peer
    public var files: [ShareFile]

    /// A message rather than files: text sent on its own (as a text file whose preview is the text).
    public var text: String? {
        guard files.count == 1, files[0].fileType.hasPrefix("text/"), let text = files[0].preview else { return nil }
        return text
    }
}

/// A transfer received: the files saved (where), or a message.
public struct ReceivedTransfer: Sendable {
    public var from: Peer
    public var files: [URL]
    public var text: String?
}
