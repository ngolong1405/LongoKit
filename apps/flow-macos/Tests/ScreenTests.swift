import XCTest
@testable import LongoFlowKit

/// Where the pointer leaves and comes in, with one screen and with two.
final class ScreenTests: XCTestCase {
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let monitor = CGRect(x: 1512, y: -400, width: 2560, height: 1440)

    func testLeavingOnTheRight() {
        let fraction = Screens.leaving(CGPoint(x: 1511, y: 491), dx: 3, dy: 0, side: .right, screens: [laptop])
        XCTAssertEqual(fraction ?? -1, 0.5, accuracy: 0.01)
        // Moving the other way, or away from the edge: it stays.
        XCTAssertNil(Screens.leaving(CGPoint(x: 1511, y: 491), dx: -3, dy: 0, side: .right, screens: [laptop]))
        XCTAssertNil(Screens.leaving(CGPoint(x: 700, y: 491), dx: 3, dy: 0, side: .right, screens: [laptop]))
    }

    func testAScreenBetweenIsntAnEdge() {
        // With a monitor on the right, the laptop's right edge leads to the monitor, not the other Mac.
        XCTAssertNil(Screens.leaving(CGPoint(x: 1511, y: 300), dx: 3, dy: 0, side: .right, screens: [laptop, monitor]))
        XCTAssertNotNil(Screens.leaving(CGPoint(x: 4071, y: 300), dx: 3, dy: 0, side: .right, screens: [laptop, monitor]))
    }

    func testComingInOnTheLeft() {
        let point = Screens.entry(.left, 0.5, screens: [laptop])
        XCTAssertEqual(point.x, 2)
        XCTAssertEqual(point.y, 490.5, accuracy: 1)
        XCTAssertTrue(laptop.contains(point))
    }

    func testKeptOnAScreen() {
        XCTAssertEqual(Screens.clamp(CGPoint(x: -50, y: 2000), screens: [laptop]), CGPoint(x: 0, y: 981))
    }
}
