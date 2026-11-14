import CryptoKit
import Foundation

/// The receiving side of LocalSend: answers /register and /info, asks before accepting files (or takes them from a
/// trusted device at once), checks the PIN, and writes each upload straight to disk, checking its SHA-256 if given.
/// One transfer at a time, as LocalSend does: another one meanwhile is told to wait (409).
final class Receiver: @unchecked Sendable {
    private let me: @Sendable () -> DeviceInfo
    private let lock = NSLock()
    private var session: Session?

    /// Asks the person whether to take files; true takes them.
    var ask: @Sendable (IncomingTransfer) async -> Bool = { _ in false }
    /// A device announced itself (or answered): it's on the network.
    var registered: @Sendable (Peer) -> Void = { _ in }
    /// Files are on their way in (asked and accepted, or from a trusted device).
    var accepted: @Sendable (IncomingTransfer) -> Void = { _ in }
    /// Bytes received so far of a transfer, and its total.
    var progress: @Sendable (Int64, Int64) -> Void = { _, _ in }
    var received: @Sendable (ReceivedTransfer) -> Void = { _ in }
    /// The sender cancelled, or a file failed.
    var cancelled: @Sendable () -> Void = {}

    private var _folder: URL
    private var _pin: String?
    private var _trusted: Set<String> = []
    var folder: URL { get { locked { _folder } } set { locked { _folder = newValue } } }
    var pin: String? { get { locked { _pin } } set { locked { _pin = newValue } } }
    var trusted: Set<String> { get { locked { _trusted } } set { locked { _trusted = newValue } } }

    private final class Session {
        let id = UUID().uuidString
        let from: Peer
        let files: [String: ShareFile]
        let tokens: [String: String]
        var saved: [String: URL] = [:]
        var partial: Set<URL> = []
        let total: Int64
        var done: Int64 = 0

        init(from: Peer, files: [String: ShareFile]) {
            self.from = from
            self.files = files
            tokens = files.mapValues { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
            total = files.values.reduce(0) { $0 + $1.size }
        }
    }

    init(me: @escaping @Sendable () -> DeviceInfo, folder: URL) {
        self.me = me
        _folder = folder
    }

    var isBusy: Bool { locked { session != nil } }

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        switch (request.method, request.path) {
        case ("POST", ShareProtocol.register):
            if let info = await request.json(DeviceInfo.self), !request.remote.isEmpty {
                registered(Peer(info: info, address: request.remote))
            }
            return .json(me())
        case ("GET", ShareProtocol.info):
            return .json(me())
        case ("POST", ShareProtocol.prepareUpload):
            return await prepare(request)
        case ("POST", ShareProtocol.upload):
            return await upload(request)
        case ("POST", ShareProtocol.cancel):
            cancel(request["sessionId"])
            return HTTPResponse(200)
        default:
            return HTTPResponse(404)
        }
    }

    private func prepare(_ request: HTTPRequest) async -> HTTPResponse {
        guard let prepare = await request.json(PrepareUploadRequest.self) else { return HTTPResponse(400) }
        if let pin, !pin.isEmpty, request["pin"] != pin { return HTTPResponse(401) }
        if isBusy { return HTTPResponse(409) }
        let from = Peer(info: prepare.info, address: request.remote)
        registered(from)
        let incoming = IncomingTransfer(from: from, files: Array(prepare.files.values).sorted { $0.fileName < $1.fileName })
        let isTrusted = !prepare.info.fingerprint.isEmpty && trusted.contains(prepare.info.fingerprint)
        if !isTrusted, !(await ask(incoming)) { return HTTPResponse(403) }
        // A message alone: nothing to upload.
        if let text = incoming.text {
            received(ReceivedTransfer(from: from, files: [], text: text))
            return HTTPResponse(204)
        }
        if prepare.files.isEmpty { return HTTPResponse(204) }
        let started: Session? = locked {
            if session != nil { return nil }
            session = Session(from: from, files: prepare.files)
            return session
        }
        guard let started else { return HTTPResponse(409) }
        accepted(incoming)
        return .json(PrepareUploadResponse(sessionId: started.id, files: started.tokens))
    }

    private func upload(_ request: HTTPRequest) async -> HTTPResponse {
        guard let sessionId = request["sessionId"], let fileId = request["fileId"], let token = request["token"] else { return HTTPResponse(400) }
        let current: Session? = locked { session?.id == sessionId ? session : nil }
        guard let current, current.tokens[fileId] == token, let file = current.files[fileId] else { return HTTPResponse(403) }
        // Only from the device the session is with.
        if request.remote != current.from.address { return HTTPResponse(403) }

        let url = Self.destination(for: file.fileName, in: folder)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw HTTPError.malformed }
            locked { current.partial.insert(url) }
            let handle = try FileHandle(forWritingTo: url)
            var hash = SHA256()
            var written: Int64 = 0
            do {
                while let chunk = try await request.body.read(), !chunk.isEmpty {
                    try handle.write(contentsOf: chunk)
                    if file.sha256 != nil { hash.update(data: chunk) }
                    written += Int64(chunk.count)
                    let (done, total) = locked { () -> (Int64, Int64) in
                        current.done += Int64(chunk.count)
                        return (current.done, current.total)
                    }
                    progress(done, total)
                    if locked({ session !== current }) { throw CancellationError() }
                }
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
            if written != file.size {
                throw HTTPError.closed
            }
            if let expected = file.sha256?.lowercased(),
               hash.finalize().map({ String(format: "%02x", $0) }).joined() != expected {
                try? FileManager.default.removeItem(at: url)
                locked { _ = current.partial.remove(url) }
                return HTTPResponse(422)
            }
            if let modified = file.metadata?.modified.flatMap(Self.date) {
                try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            locked { _ = current.partial.remove(url) }
            failed(current)
            return HTTPResponse(500)
        }

        let finished: ReceivedTransfer? = locked {
            current.partial.remove(url)
            current.saved[fileId] = url
            guard current.saved.count == current.files.count, session === current else { return nil }
            session = nil
            let urls = current.files.keys.sorted().compactMap { current.saved[$0] }
            return ReceivedTransfer(from: current.from, files: urls, text: nil)
        }
        if let finished { received(finished) }
        return HTTPResponse(200)
    }

    /// Ends the transfer under way (the sender's /cancel, or the person here), removing half-written files.
    func cancel(_ sessionId: String? = nil) {
        let ended: Session? = locked {
            guard let current = session, sessionId == nil || current.id == sessionId else { return nil }
            session = nil
            return current
        }
        guard let ended else { return }
        for url in ended.partial { try? FileManager.default.removeItem(at: url) }
        cancelled()
    }

    private func failed(_ current: Session) {
        let ended = locked { () -> Bool in
            guard session === current else { return false }
            session = nil
            return true
        }
        if ended { cancelled() }
    }

    /// Where a sent name goes: inside the folder whatever it says (no "..", no drive or root), and not over a file
    /// that's there already ("photo (1).jpg").
    static func destination(for name: String, in folder: URL) -> URL {
        let parts = name.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
            .map { $0.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        var url = folder
        for part in parts.dropLast() { url.appendPathComponent(part, isDirectory: true) }
        let file = parts.last ?? "file"
        let base = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        var candidate = url.appendingPathComponent(file)
        var number = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.appendingPathComponent(ext.isEmpty ? "\(base) (\(number))" : "\(base) (\(number)).\(ext)")
            number += 1
        }
        return candidate
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private func locked<T>(_ work: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return work()
    }
}
