import XCTest
@testable import LongoFlowKit

/// Where the pointer goes over, with several displays on each Mac, and where a dropped Mac snaps to.
final class ScreenTests: XCTestCase {
    // This Mac: a laptop with a monitor to its left (as macOS arranges them, the laptop's top-left at 0,0).
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let monitor = CGRect(x: -2560, y: -458, width: 2560, height: 1440)
    // The other Mac: one laptop screen, in its own coordinates.
    private let air = [CGRect(x: 0, y: 0, width: 1470, height: 956)]

    func testOverTheRightEdgeOntoTheOtherMac() {
        // The other Mac placed right of the laptop, tops level.
        let there = Screens.crossing(CGPoint(x: 1511, y: 400), dx: 4, dy: 0, local: [laptop, monitor], into: air, at: CGPoint(x: 1512, y: 0))
        XCTAssertNotNil(there)
        XCTAssertEqual(there!.y, 400, accuracy: 1)
        XCTAssertLessThan(there!.x, 10)
    }

    func testFromTheMonitorWhereTheOtherMacIs() {
        // The other Mac placed left of the monitor: the monitor's left edge leads there, the laptop's right doesn't.
        let offset = CGPoint(x: -2560 - 1470, y: 0)
        XCTAssertNotNil(Screens.crossing(CGPoint(x: -2560, y: 100), dx: -3, dy: 0, local: [laptop, monitor], into: air, at: offset))
        XCTAssertNil(Screens.crossing(CGPoint(x: 1511, y: 100), dx: 3, dy: 0, local: [laptop, monitor], into: air, at: offset))
    }

    func testBetweenTwoOwnDisplaysStaysHere() {
        // From the laptop into the monitor: still this Mac.
        XCTAssertNil(Screens.crossing(CGPoint(x: 0, y: 300), dx: -3, dy: 0, local: [laptop, monitor], into: air, at: CGPoint(x: 1512, y: 0)))
    }

    func testOnlyWhereTheyTouch() {
        // The other Mac right of the laptop but lower: above where it starts, the edge is just an edge.
        let offset = CGPoint(x: 1512, y: 600)
        XCTAssertNil(Screens.crossing(CGPoint(x: 1511, y: 200), dx: 3, dy: 0, local: [laptop], into: air, at: offset))
        XCTAssertNotNil(Screens.crossing(CGPoint(x: 1511, y: 800), dx: 3, dy: 0, local: [laptop], into: air, at: offset))
    }

    func testADroppedMacSnapsEdgeToEdge() {
        // Dropped a bit off, to the right of the laptop: it snaps against its right edge.
        let snapped = Screens.snap(air, at: CGPoint(x: 1600, y: 40), to: [laptop, monitor])
        XCTAssertEqual(snapped.x, 1512)
        XCTAssertEqual(snapped.y, 40)
        // Dropped over the laptop: moved off it, still touching.
        let off = Screens.snap(air, at: CGPoint(x: 900, y: 100), to: [laptop])
        let placed = CGRect(origin: off, size: air[0].size)
        XCTAssertFalse(laptop.insetBy(dx: 1, dy: 1).intersects(placed))
        XCTAssertTrue(laptop.insetBy(dx: -1, dy: -1).intersects(placed))
    }

    func testAMacPairedBeforeScreensWereKnownKeepsItsSide() throws {
        // Saved by the first build: no screens, no offset.
        let json = #"[{"id":"air","name":"Air","key":"AAAA","side":1}]"#
        let macs = try JSONDecoder().decode([PairedMac].self, from: Data(json.utf8))
        XCTAssertEqual(macs[0].side, .right)
        XCTAssertNil(macs[0].offset)
        XCTAssertEqual(macs[0].placed(next: [laptop]).x, laptop.maxX)
    }

    func testKeptOnAScreen() {
        XCTAssertEqual(Screens.clamp(CGPoint(x: 3000, y: 2000), screens: [laptop]), CGPoint(x: 1511, y: 981))
    }
}
