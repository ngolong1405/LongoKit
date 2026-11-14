import XCTest
@testable import LongoShareKit

/// Two devices in one process, on their own ports, talking LocalSend over HTTP.
final class TransferTests: XCTestCase {
    private var folders: [URL] = []

    override func tearDown() {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
    }

    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LongoShareTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folders.append(url)
        return url
    }

    private func node(_ alias: String, port: Int, trusted: Set<String> = [], pin: String? = nil) async throws -> ShareNode {
        var settings = ShareSettings(alias: alias, fingerprint: alias.lowercased(), folder: folder(), pin: pin, trusted: trusted)
        settings.port = port
        let node = ShareNode(settings: settings)
        let error: Error? = await withCheckedContinuation { continuation in node.start(discover: false) { continuation.resume(returning: $0) } }
        if let error { throw error }
        return node
    }

    private func peer(_ node: ShareNode) -> Peer {
        Peer(info: node.me, address: "127.0.0.1")
    }

    func testFilesFromATrustedDeviceComeInWithoutAsking() async throws {
        let receiver = try await node("Mac", port: 53411, trusted: ["pc"])
        let sender = try await node("PC", port: 53412)
        defer { receiver.stop(); sender.stop() }
        let received = expectation(description: "received")
        var saved: [URL] = []
        receiver.receiver.received = { transfer in
            saved = transfer.files
            received.fulfill()
        }
        let source = folder()
        let small = source.appendingPathComponent("hello.txt")
        try Data("xin chào".utf8).write(to: small)
        let big = source.appendingPathComponent("big.bin")
        try Data((0..<3_000_000).map { UInt8($0 % 251) }).write(to: big)

        let result = await sender.send(to: peer(receiver), items: [.file(small), .file(big)]) { _, _ in }
        XCTAssertEqual(result, .sent)
        await fulfillment(of: [received], timeout: 10)
        XCTAssertEqual(Set(saved.map(\.lastPathComponent)), ["hello.txt", "big.bin"])
        XCTAssertEqual(try Data(contentsOf: saved.first { $0.lastPathComponent == "big.bin" }!), try Data(contentsOf: big))
        XCTAssertEqual(String(decoding: try Data(contentsOf: saved.first { $0.lastPathComponent == "hello.txt" }!), as: UTF8.self), "xin chào")
    }

    func testAskedAndDeclined() async throws {
        let receiver = try await node("Mac", port: 53413)
        let sender = try await node("PC", port: 53414)
        defer { receiver.stop(); sender.stop() }
        receiver.receiver.ask = { transfer in transfer.from.info.alias == "PC" ? false : true }
        let file = folder().appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: file)
        let result = await sender.send(to: peer(receiver), items: [.file(file)]) { _, _ in }
        XCTAssertEqual(result, .rejected)
    }

    func testAMessage() async throws {
        let receiver = try await node("Mac", port: 53415)
        let sender = try await node("PC", port: 53416)
        defer { receiver.stop(); sender.stop() }
        receiver.receiver.ask = { _ in true }
        let received = expectation(description: "message")
        var text: String?
        receiver.receiver.received = { transfer in
            text = transfer.text
            received.fulfill()
        }
        let result = await sender.send(to: peer(receiver), items: [.message("Gửi bạn link nè")]) { _, _ in }
        XCTAssertEqual(result, .sent)
        await fulfillment(of: [received], timeout: 5)
        XCTAssertEqual(text, "Gửi bạn link nè")
    }

    func testAPin() async throws {
        let receiver = try await node("Mac", port: 53417, trusted: ["pc"], pin: "4821")
        let sender = try await node("PC", port: 53418)
        defer { receiver.stop(); sender.stop() }
        let file = folder().appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: file)
        let without = await sender.send(to: peer(receiver), items: [.file(file)]) { _, _ in }
        XCTAssertEqual(without, .pinRequired)
        let wrong = await sender.send(to: peer(receiver), items: [.file(file)], pin: "0000") { _, _ in }
        XCTAssertEqual(wrong, .pinRequired)
        let right = await sender.send(to: peer(receiver), items: [.file(file)], pin: "4821") { _, _ in }
        XCTAssertEqual(right, .sent)
    }

    func testRegisterIntroducesBothWays() async throws {
        let a = try await node("Mac", port: 53419)
        let b = try await node("PC", port: 53420)
        defer { a.stop(); b.stop() }
        let found = await a.connect("127.0.0.1", port: 53420)
        XCTAssertEqual(found?.info.alias, "PC")
        XCTAssertEqual(found?.info.protocol, "http")
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(b.list.map(\.info.alias), ["Mac"])
    }

    /// Longo Share for Windows (.NET) uploads chunked; so may others.
    func testAChunkedUpload() async throws {
        let receiver = try await node("Mac", port: 53421, trusted: ["pc"])
        defer { receiver.stop() }
        let body = #"{"info":{"alias":"PC","fingerprint":"pc","port":1,"protocol":"http"},"files":{"f1":{"id":"f1","fileName":"..\/..\/evil\/c.txt","size":11,"fileType":"text/plain-file"}}}"#
        var prepare = URLRequest(url: URL(string: "http://127.0.0.1:53421/api/localsend/v2/prepare-upload")!)
        prepare.httpMethod = "POST"
        prepare.httpBody = Data(body.utf8)
        let (data, response) = try await URLSession.shared.data(for: prepare)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let answer = try JSONDecoder().decode(PrepareUploadResponse.self, from: data)
        let received = expectation(description: "received")
        var saved: [URL] = []
        receiver.receiver.received = { saved = $0.files; received.fulfill() }

        let url = URL(string: "http://127.0.0.1:53421/api/localsend/v2/upload?sessionId=\(answer.sessionId)&fileId=f1&token=\(answer.files["f1"]!)")!
        var upload = URLRequest(url: url)
        upload.httpMethod = "POST"
        // A stream body goes chunked.
        upload.httpBodyStream = InputStream(data: Data("hello world".utf8))
        let (_, uploaded) = try await URLSession.shared.data(for: upload)
        XCTAssertEqual((uploaded as? HTTPURLResponse)?.statusCode, 200)
        await fulfillment(of: [received], timeout: 5)
        // Kept inside the folder, whatever the name says.
        XCTAssertTrue(saved[0].path.hasPrefix(receiver.settings.folder.path))
        XCTAssertEqual(saved[0].lastPathComponent, "c.txt")
        XCTAssertEqual(try String(contentsOf: saved[0]), "hello world")
    }

    func testDestinationsStayInTheFolder() {
        let base = URL(fileURLWithPath: "/tmp/in")
        XCTAssertEqual(Receiver.destination(for: "../../etc/passwd", in: base).path, "/tmp/in/etc/passwd")
        XCTAssertEqual(Receiver.destination(for: #"C:\Windows\evil.dll"#, in: base).path, "/tmp/in/C/Windows/evil.dll")
        XCTAssertEqual(Receiver.destination(for: "/abs/photo.jpg", in: base).path, "/tmp/in/abs/photo.jpg")
    }
}
