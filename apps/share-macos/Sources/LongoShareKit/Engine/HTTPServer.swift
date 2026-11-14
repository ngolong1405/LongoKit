import Foundation
import Network

/// A request: its line and headers read, its body read as the handler goes (an upload streams straight to disk).
final class HTTPRequest: @unchecked Sendable {
    let method: String
    let path: String
    let query: [String: String]
    /// Lowercased names.
    let headers: [String: String]
    /// The sender's IP address.
    let remote: String
    let body: HTTPBody

    init(method: String, path: String, query: [String: String], headers: [String: String], remote: String, body: HTTPBody) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.remote = remote
        self.body = body
    }

    subscript(name: String) -> String? { query[name] }

    /// The whole body as JSON (small bodies only).
    func json<T: Decodable>(_ type: T.Type) async -> T? {
        var data = Data()
        while let chunk = try? await body.read(), !chunk.isEmpty {
            data.append(chunk)
            if data.count > 8 << 20 { return nil }
        }
        return try? ShareProtocol.decoder.decode(type, from: data)
    }
}

struct HTTPResponse {
    var status: Int
    var body = Data()
    var contentType = "application/json"

    init(_ status: Int, body: Data = Data(), contentType: String = "application/json") {
        self.status = status
        self.body = body
        self.contentType = contentType
    }

    static func json<T: Encodable>(_ value: T) -> HTTPResponse {
        HTTPResponse(200, body: (try? ShareProtocol.encoder.encode(value)) ?? Data())
    }
}

enum HTTPError: Error {
    case closed, malformed, tooLarge
}

/// A small HTTP/1.1 server: one connection after another, keep-alive, bodies by Content-Length or chunked.
final class HTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let handler: @Sendable (HTTPRequest) async -> HTTPResponse
    private let queue = DispatchQueue(label: "LongoShare.server")

    init(port: Int, handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(port)))
        self.handler = handler
    }

    /// Starts listening; calls `ready` once with nil, or with the error that stopped it (the port is taken).
    func start(ready: @escaping @Sendable (Error?) -> Void) {
        var reported = false
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready where !reported:
                reported = true
                ready(nil)
            case .failed(let error) where !reported:
                reported = true
                ready(error)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            Task { await self.serve(Connection(connection)) }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
    }

    private func serve(_ connection: Connection) async {
        defer { connection.close() }
        do {
            while true {
                let head = try await connection.readHead()
                guard let request = Self.parse(head, connection: connection) else {
                    try await connection.write(HTTPResponse(400), keepAlive: false)
                    return
                }
                let response = await handler(request)
                // What the handler left of the body is read away, so the next request starts where it should.
                var left = 0
                while let chunk = try await request.body.read(), !chunk.isEmpty {
                    left += chunk.count
                    if left > 1 << 20 { return }
                }
                let keepAlive = request.headers["connection"]?.lowercased() != "close"
                try await connection.write(response, keepAlive: keepAlive)
                if !keepAlive { return }
            }
        } catch {
            // The other side went away.
        }
    }

    private static func parse(_ head: String, connection: Connection) -> HTTPRequest? {
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let target = String(parts[1])
        let components = URLComponents(string: "http://host" + target)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let body: HTTPBody
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            body = ChunkedBody(connection)
        } else {
            body = LengthBody(connection, length: Int64(headers["content-length"] ?? "0") ?? 0)
        }
        return HTTPRequest(method: String(parts[0]), path: components?.path ?? target, query: query, headers: headers,
                           remote: connection.remote, body: body)
    }
}

/// A request's body, read a piece at a time; an empty piece (or nil) is its end.
protocol HTTPBody: AnyObject, Sendable {
    func read() async throws -> Data?
}

private final class LengthBody: HTTPBody, @unchecked Sendable {
    private let connection: Connection
    private var remaining: Int64

    init(_ connection: Connection, length: Int64) {
        self.connection = connection
        remaining = length
    }

    func read() async throws -> Data? {
        guard remaining > 0 else { return nil }
        let data = try await connection.read(max: Int(min(remaining, 1 << 20)))
        remaining -= Int64(data.count)
        return data
    }
}

private final class ChunkedBody: HTTPBody, @unchecked Sendable {
    private let connection: Connection
    private var inChunk: Int64 = 0
    private var done = false

    init(_ connection: Connection) { self.connection = connection }

    func read() async throws -> Data? {
        if done { return nil }
        if inChunk == 0 {
            let line = try await connection.readLine()
            let size = line.split(separator: ";").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard let length = Int64(size, radix: 16) else { throw HTTPError.malformed }
            if length == 0 {
                // Trailers, up to the empty line.
                while !(try await connection.readLine()).isEmpty {}
                done = true
                return nil
            }
            inChunk = length
        }
        let data = try await connection.read(max: Int(min(inChunk, 1 << 20)))
        inChunk -= Int64(data.count)
        if inChunk == 0 { _ = try await connection.readLine() }
        return data
    }
}

/// One TCP connection, read with async calls over what's come in so far.
private final class Connection: @unchecked Sendable {
    private let connection: NWConnection
    private var buffer = Data()
    let remote: String

    init(_ connection: NWConnection) {
        self.connection = connection
        if case .hostPort(let host, _) = connection.endpoint {
            var text = "\(host)"
            // IPv4 over an IPv6 socket, and a link's scope, aren't part of the address.
            if text.hasPrefix("::ffff:") { text.removeFirst(7) }
            if let percent = text.firstIndex(of: "%") { text = String(text[..<percent]) }
            remote = text
        } else {
            remote = ""
        }
    }

    private func receive() async throws {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, complete, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, !data.isEmpty { continuation.resume(returning: data) }
                else if complete { continuation.resume(throwing: HTTPError.closed) }
                else { continuation.resume(returning: Data()) }
            }
        }
        buffer.append(data)
    }

    /// Up to the blank line after the headers.
    func readHead() async throws -> String {
        let end = Data("\r\n\r\n".utf8)
        while true {
            // A TLS handshake (a client trying HTTPS): closed at once, so it can try HTTP without waiting.
            if buffer.first == 0x16 { throw HTTPError.malformed }
            if let range = buffer.range(of: end) {
                let head = String(decoding: buffer[buffer.startIndex..<range.lowerBound], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return head
            }
            if buffer.count > 64 << 10 { throw HTTPError.tooLarge }
            try await receive()
        }
    }

    func readLine() async throws -> String {
        let end = Data("\r\n".utf8)
        while true {
            if let range = buffer.range(of: end) {
                let line = String(decoding: buffer[buffer.startIndex..<range.lowerBound], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return line
            }
            if buffer.count > 8 << 10 { throw HTTPError.tooLarge }
            try await receive()
        }
    }

    func read(max: Int) async throws -> Data {
        if buffer.isEmpty { try await receive() }
        let count = min(max, buffer.count)
        let data = Data(buffer.prefix(count))
        buffer.removeFirst(count)
        return data
    }

    func write(_ response: HTTPResponse, keepAlive: Bool) async throws {
        var head = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\n"
        head += "Content-Length: \(response.body.count)\r\n"
        if !response.body.isEmpty { head += "Content-Type: \(response.contentType)\r\n" }
        head += keepAlive ? "Connection: keep-alive\r\n\r\n" : "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(response.body)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    func close() {
        connection.cancel()
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 409: return "Conflict"
        case 422: return "Unprocessable Entity"
        case 429: return "Too Many Requests"
        default: return status < 400 ? "OK" : "Error"
        }
    }
}
