import XCTest
@testable import NotchAgent

final class TimeTintTests: XCTestCase {
    func testTintOnlyAppliesWithoutWeather() {
        // The layer's visibility rule is a pure predicate on the two toggles.
        XCTAssertTrue(TimeTintVisibleRule.evaluate(delightEnabled: true, weatherEnabled: false))
        XCTAssertFalse(TimeTintVisibleRule.evaluate(delightEnabled: true, weatherEnabled: true))
        XCTAssertFalse(TimeTintVisibleRule.evaluate(delightEnabled: false, weatherEnabled: false))
        XCTAssertFalse(TimeTintVisibleRule.evaluate(delightEnabled: false, weatherEnabled: true))
    }
}
