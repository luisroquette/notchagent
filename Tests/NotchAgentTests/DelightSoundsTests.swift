import XCTest
@testable import NotchAgent

final class DelightSoundsTests: XCTestCase {
    func testEligibilityGates() {
        XCTAssertTrue(DelightSounds.eligibility(enabled: true, reduceMotion: false, screenReader: false))
        XCTAssertFalse(DelightSounds.eligibility(enabled: false, reduceMotion: false, screenReader: false))
        XCTAssertFalse(DelightSounds.eligibility(enabled: true, reduceMotion: true, screenReader: false))
        XCTAssertFalse(DelightSounds.eligibility(enabled: true, reduceMotion: false, screenReader: true))
    }
}
