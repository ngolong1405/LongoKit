import Network
import XCTest
@testable import LongoFlowKit

/// Two Macs in one process, on loopback: pairing with the code, then the encrypted link.
final class LinkTests: XCTestCase {
    private func start(_ node: FlowNode) async -> UInt16 {
        await withCheckedContinuation { continuation in node.start(bonjour: false) { continuation.resume(returning: $0 ?? 0) } }
    }

    private func nearby(_ id: String, _ name: String, _ port: UInt16) -> NearbyMac {
        NearbyMac(id: id, name: name, endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!))
    }

    /// Pairs `a` (asking) with `b`, typing `code` (or the right one).
    private func pair(_ a: FlowNode, _ b: FlowNode, wrong: Bool = false) async -> Bool {
        let shown = expectation(description: "code")
        let asked = expectation(description: "asked")
        var code = ""
        b.showCode = { value, _ in if let value { code = value; shown.fulfill() } }
        a.needsCode = { _ in asked.fulfill() }
        let ended = expectation(description: "ended")
        // After a wrong code, the test stopping the other Mac ends the pairing too.
        ended.assertForOverFulfill = false
        var result = false
        a.pairingEnded = { _, ok in result = ok; ended.fulfill() }
        a.codeRejected = { _ in result = false; ended.fulfill() }
        a.pair(with: b.id, side: .right)
        await fulfillment(of: [shown, asked], timeout: 5)
        b.showCode = { _, _ in }
        a.submit(code: wrong ? String(code.reversed()) + "9" : code)
        await fulfillment(of: [ended], timeout: 5)
        return result
    }

    func testPairingThenAnEncryptedLink() async throws {
        let a = FlowNode(id: "a-mac", name: "Mac A", paired: [])
        let b = FlowNode(id: "b-mac", name: "Mac B", paired: [])
        defer { a.stop(); b.stop() }
        let portA = await start(a)
        let portB = await start(b)
        a.add(nearby("b-mac", "Mac B", portB))
        b.add(nearby("a-mac", "Mac A", portA))

        let linked = expectation(description: "linked")
        linked.assertForOverFulfill = false
        a.connectedChanged = { if $0.contains("b-mac") { linked.fulfill() } }
        let paired = await pair(a, b)
        XCTAssertTrue(paired)
        XCTAssertEqual(a.pairedMacs.first?.side, .right)
        XCTAssertEqual(b.pairedMacs.first?.side, .left)
        XCTAssertEqual(a.pairedMacs.first?.key, b.pairedMacs.first?.key)
        await fulfillment(of: [linked], timeout: 8)

        // A pointer move, sealed, both ways.
        let got = expectation(description: "move")
        var dx: Float = 0
        b.received = { from, message in
            guard from == "a-mac", message.kind == .move else { return }
            var reader = Reader(message.payload)
            dx = reader.f32() ?? 0
            got.fulfill()
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        var writer = Writer()
        writer.f32(12.5)
        writer.f32(-3)
        a.send(Message(.move, writer.data), to: "b-mac")
        await fulfillment(of: [got], timeout: 5)
        XCTAssertEqual(dx, 12.5)

        // A big clipboard doesn't hold the pointer up: a move sent after it arrives first, and the picture whole.
        let big = Data((0..<3_000_000).map { UInt8($0 % 253) })
        let both = expectation(description: "both")
        both.expectedFulfillmentCount = 2
        var order: [Kind] = []
        var clipboard = Data()
        b.received = { _, message in
            guard message.kind == .clipboard || message.kind == .move else { return }
            order.append(message.kind)
            if message.kind == .clipboard { clipboard = message.payload }
            both.fulfill()
        }
        a.sendBulk(Message(.clipboard, big), to: "b-mac")
        a.send(Message(.move, writer.data), to: "b-mac")
        await fulfillment(of: [both], timeout: 10)
        XCTAssertEqual(order, [.move, .clipboard])
        XCTAssertEqual(clipboard, big)

        // Moving B in A's arrangement: B takes the inverse, and says so.
        let confirmed = expectation(description: "placed")
        a.placedThere = { if $0 == "b-mac" { confirmed.fulfill() } }
        a.place("b-mac", at: CGPoint(x: 1512, y: 40))
        await fulfillment(of: [confirmed], timeout: 5)
        XCTAssertEqual(b.pairedMacs.first?.offset, CGPoint(x: -1512, y: -40))
    }

    func testAWrongCodeDoesntPair() async throws {
        let a = FlowNode(id: "a-mac", name: "Mac A", paired: [])
        let b = FlowNode(id: "b-mac", name: "Mac B", paired: [])
        defer { a.stop(); b.stop() }
        _ = await start(a)
        let portB = await start(b)
        a.add(nearby("b-mac", "Mac B", portB))
        let paired = await pair(a, b, wrong: true)
        XCTAssertFalse(paired)
        XCTAssertTrue(a.pairedMacs.isEmpty)
        XCTAssertTrue(b.pairedMacs.isEmpty)
    }

    func testAStrangerCantLink() async throws {
        // B knows A; a third Mac claiming to be A has the wrong key, and its first sealed message doesn't open.
        let key = Keys.random(32)
        let b = FlowNode(id: "b-mac", name: "Mac B", paired: [PairedMac(id: "a-mac", name: "Mac A", key: key, side: .left)])
        let fake = FlowNode(id: "a-mac", name: "Mac A", paired: [PairedMac(id: "b-mac", name: "Mac B", key: Keys.random(32), side: .right)])
        defer { b.stop(); fake.stop() }
        let portB = await start(b)
        _ = await start(fake)
        var linked = false
        b.connectedChanged = { if !$0.isEmpty { linked = true } }
        fake.add(nearby("b-mac", "Mac B", portB))
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertFalse(linked)
    }

    func testSealedMessagesCantBeReplayed() {
        let key = SymmetricKeyData(key: .init(size: .bits256))
        var send = Cipher(key: key.key, direction: 1)
        var receive = Cipher(key: key.key, direction: 1)
        let first = send.seal(Data("one".utf8))!
        XCTAssertEqual(receive.open(first), Data("one".utf8))
        // The same message again: the counter has moved on.
        XCTAssertNil(receive.open(first))
    }
}
