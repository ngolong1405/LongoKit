import Foundation
import UniformTypeIdentifiers

public enum SendResult: Sendable {
    case sent, pinRequired, rejected, busy, failed, cancelled
}

/// Something to send: a file, or a message.
public enum Outgoing: Sendable {
    case file(URL)
    case message(String)
}

/// The sending side: asks a device to take files (prepare-upload), then uploads them, three at a time, streamed from
/// disk. Devices use self-signed certificates (LocalSend's way), so any certificate is taken; the fingerprint says who.
final class Sender: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let me: @Sendable () -> DeviceInfo
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    init(me: @escaping @Sendable () -> DeviceInfo) {
        self.me = me
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if let trust = challenge.protectionSpace.serverTrust { return (.useCredential, URLCredential(trust: trust)) }
        return (.performDefaultHandling, nil)
    }

    /// Introduces this device to one at `address`; its answer says what it is.
    func register(address: String, port: Int, protocol scheme: String, timeout: TimeInterval = 2) async -> Peer? {
        let host = address.contains(":") ? "[\(address)]" : address
        guard let url = URL(string: "\(scheme)://\(host):\(port)\(ShareProtocol.register)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? ShareProtocol.encoder.encode(me())
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              var info = try? ShareProtocol.decoder.decode(DeviceInfo.self, from: data) else { return nil }
        // The answer may leave these out: they're how it was reached.
        info.port = port
        info.protocol = scheme
        return Peer(info: info, address: address)
    }

    /// Sends `items` to `peer`; `progress` gets bytes sent and the total.
    func send(to peer: Peer, items: [Outgoing], pin: String? = nil,
              progress: @escaping @Sendable (Int64, Int64) -> Void) async -> SendResult {
        var files: [String: ShareFile] = [:]
        var sources: [String: Outgoing] = [:]
        for item in items {
            let id = UUID().uuidString
            sources[id] = item
            switch item {
            case .message(let text):
                files[id] = ShareFile(id: id, fileName: id + ".txt", size: Int64(text.utf8.count), fileType: "text/plain", preview: text)
            case .file(let url):
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let modified = values?.contentModificationDate.map { ISO8601DateFormatter().string(from: $0) }
                files[id] = ShareFile(id: id, fileName: url.lastPathComponent, size: Int64(values?.fileSize ?? 0),
                                      fileType: Self.mimeType(url), metadata: FileMetadata(modified: modified, accessed: nil))
            }
        }

        var components = URLComponents(url: peer.url(ShareProtocol.prepareUpload), resolvingAgainstBaseURL: false)!
        if let pin, !pin.isEmpty { components.queryItems = [URLQueryItem(name: "pin", value: pin)] }
        // The other side may wait for its person to answer.
        var prepare = URLRequest(url: components.url!, timeoutInterval: 300)
        prepare.httpMethod = "POST"
        prepare.setValue("application/json", forHTTPHeaderField: "Content-Type")
        prepare.httpBody = try? ShareProtocol.encoder.encode(PrepareUploadRequest(info: me(), files: files))
        let data: Data
        let status: Int
        do {
            let (body, response) = try await session.data(for: prepare)
            data = body
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            return Task.isCancelled ? .cancelled : .failed
        }
        switch status {
        case 200: break
        case 204: return .sent
        case 401: return .pinRequired
        case 403: return .rejected
        case 409: return .busy
        default: return .failed
        }
        guard let answer = try? ShareProtocol.decoder.decode(PrepareUploadResponse.self, from: data) else { return .failed }

        let total = answer.files.keys.compactMap { files[$0]?.size }.reduce(0, +)
        let counter = Counter(total: total, progress: progress)
        let ok = await withTaskGroup(of: Bool.self) { group -> Bool in
            var pending = Array(answer.files)
            var running = 0
            var allGood = true
            while !pending.isEmpty || running > 0 {
                while running < 3, let (id, token) = pending.popLast() {
                    guard let source = sources[id] else { continue }
                    running += 1
                    group.addTask { await self.upload(source, to: peer, session: answer.sessionId, file: id, token: token, counter: counter) }
                }
                guard let result = await group.next() else { break }
                running -= 1
                if !result {
                    allGood = false
                    group.cancelAll()
                    pending.removeAll()
                }
            }
            return allGood
        }
        if !ok || Task.isCancelled {
            var cancel = URLRequest(url: URL(string: peer.url(ShareProtocol.cancel).absoluteString + "?sessionId=" + answer.sessionId)!, timeoutInterval: 3)
            cancel.httpMethod = "POST"
            _ = try? await session.data(for: cancel)
            return Task.isCancelled ? .cancelled : .failed
        }
        return .sent
    }

    private func upload(_ source: Outgoing, to peer: Peer, session sessionId: String, file: String, token: String, counter: Counter) async -> Bool {
        var components = URLComponents(url: peer.url(ShareProtocol.upload), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "sessionId", value: sessionId), URLQueryItem(name: "fileId", value: file),
                                 URLQueryItem(name: "token", value: token)]
        var request = URLRequest(url: components.url!, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let delegate = UploadProgress(counter: counter)
        do {
            let response: URLResponse
            switch source {
            case .file(let url): (_, response) = try await session.upload(for: request, fromFile: url, delegate: delegate)
            case .message(let text): (_, response) = try await session.upload(for: request, from: Data(text.utf8), delegate: delegate)
            }
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    static func mimeType(_ url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    /// Bytes sent across all the uploads.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var done: Int64 = 0
        let total: Int64
        let progress: @Sendable (Int64, Int64) -> Void

        init(total: Int64, progress: @escaping @Sendable (Int64, Int64) -> Void) {
            self.total = total
            self.progress = progress
        }

        func add(_ bytes: Int64) {
            lock.lock()
            done += bytes
            let now = done
            lock.unlock()
            progress(now, total)
        }
    }

    private final class UploadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let counter: Counter
        init(counter: Counter) { self.counter = counter }

        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                        totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            counter.add(bytesSent)
        }
    }
}
