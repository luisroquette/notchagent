import XCTest
@testable import NotchAgent

final class BurnChartLabelLayoutTests: XCTestCase {
    func testFirstLabelIsNeverMoved() {
        let y = BurnChartView.nonCollidingLabelY(100, avoiding: [], minGap: 12)
        XCTAssertEqual(y, 100)
    }

    func testLabelFarFromExistingOnesIsNotMoved() {
        let y = BurnChartView.nonCollidingLabelY(200, avoiding: [100], minGap: 12)
        XCTAssertEqual(y, 200)
    }

    func testCollidingLabelIsPushedDownByExactlyOneGap() {
        let y = BurnChartView.nonCollidingLabelY(100, avoiding: [95], minGap: 12)
        XCTAssertEqual(y, 112)
    }

    func testCascadingCollisionPushesPastAllOccupiedSlots() {
        // 100 collides with 95 -> tries 112, which collides with 108 -> tries 124, clear.
        let y = BurnChartView.nonCollidingLabelY(100, avoiding: [95, 108], minGap: 12)
        XCTAssertEqual(y, 124)
    }

    func testExactBoundaryGapCountsAsClear() {
        // Exactly minGap apart is NOT a collision (< minGap is; == is fine).
        let y = BurnChartView.nonCollidingLabelY(112, avoiding: [100], minGap: 12)
        XCTAssertEqual(y, 112)
    }
}
