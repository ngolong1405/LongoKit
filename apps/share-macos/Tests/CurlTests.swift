import XCTest
@testable import LongoShareKit

/// Clients other than URLSession: curl asks "Expect: 100-continue" before a body over 1 KB.
final class CurlTests: XCTestCase {
    func testAnUploadThatExpectsContinue() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("LongoShareCurl-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        var settings = ShareSettings(alias: "Mac", fingerprint: "mac", folder: folder, trusted: ["pc"])
        settings.port = 53431
        let node = ShareNode(settings: settings)
        let error: Error? = await withCheckedContinuation { continuation in node.start(discover: false) { continuation.resume(returning: $0) } }
        XCTAssertNil(error)
        defer { node.stop() }
        let body = Data((0..<200_000).map { UInt8($0 % 251) })
        let source = folder.deletingLastPathComponent().appendingPathComponent("curl-src-\(UUID().uuidString).bin")
        try body.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        var prepare = URLRequest(url: URL(string: "http://127.0.0.1:53431/api/localsend/v2/prepare-upload")!)
        prepare.httpMethod = "POST"
        prepare.httpBody = Data(#"{"info":{"alias":"PC","fingerprint":"pc","port":1,"protocol":"http"},"files":{"f":{"id":"f","fileName":"a.bin","size":200000,"fileType":"application/octet-stream"}}}"#.utf8)
        let (data, _) = try await URLSession.shared.data(for: prepare)
        let answer = try JSONDecoder().decode(PrepareUploadResponse.self, from: data)

        let curl = Process()
        curl.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        curl.arguments = ["-s", "-m", "8", "-o", "/dev/null", "-w", "%{http_code}", "-X", "POST",
                          "http://127.0.0.1:53431/api/localsend/v2/upload?sessionId=\(answer.sessionId)&fileId=f&token=\(answer.files["f"]!)",
                          "--data-binary", "@\(source.path)"]
        let out = Pipe()
        curl.standardOutput = out
        try curl.run()
        curl.waitUntilExit()
        XCTAssertEqual(String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), "200")
    }
}
