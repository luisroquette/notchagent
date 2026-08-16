import XCTest
@testable import NotchAgent

final class BurnChartLabelLayoutTests: XCTestCase {
    func testFirstLabelIsNeverMoved() {
        let y = BurnChartView.nonCollidingLabelY(100, avoiding: [], minGap: 12, clampedTo: 0...1000)
        XCTAssertEqual(y, 100)
    }

    func testLabelFarFromExistingOnesIsNotMoved() {
        let y = BurnChartView.nonCollidingLabelY(200, avoiding: [100], minGap: 12, clampedTo: 0...1000)
        XCTAssertEqual(y, 200)
    }

    func testCollidingLabelIsPushedDownByExactlyOneGap() {
        let y = BurnChartView.nonCollidingLabelY(100, avoiding: [95], minGap: 12, clampedTo: 0...1000)
        XCTAssertEqual(y, 112)
    }

    func testCascadingCollisionPushesPastAllOccupiedSlots() {
        // 100 collides with 95 -> tries 112, which collides with 108 -> tries 124, clear.
        let y = BurnChartView.nonCollidingLabelY(100, avoiding: [95, 108], minGap: 12, clampedTo: 0...1000)
        XCTAssertEqual(y, 124)
    }

    func testExactBoundaryGapCountsAsClear() {
        // Exactly minGap apart is NOT a collision (< minGap is; == is fine).
        let y = BurnChartView.nonCollidingLabelY(112, avoiding: [100], minGap: 12, clampedTo: 0...1000)
        XCTAssertEqual(y, 112)
    }

    func testLabelBelowLowerBoundIsRaisedToIt() {
        let y = BurnChartView.nonCollidingLabelY(-10, avoiding: [], minGap: 12, clampedTo: 6...400)
        XCTAssertEqual(y, 6)
    }

    func testLabelAboveUpperBoundIsLoweredToIt() {
        let y = BurnChartView.nonCollidingLabelY(500, avoiding: [], minGap: 12, clampedTo: 6...400)
        XCTAssertEqual(y, 400)
    }

    func testCollisionNudgeStopsAtUpperBoundInsteadOfLoopingForever() {
        // Bounds only fit one more slot above the placed label at 390;
        // a naive nudge-forever loop would hang here.
        let y = BurnChartView.nonCollidingLabelY(388, avoiding: [390], minGap: 12, clampedTo: 6...400)
        XCTAssertLessThanOrEqual(y, 400)
    }
}
