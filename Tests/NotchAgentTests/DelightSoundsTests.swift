import XCTest
@testable import NotchAgent

final class DelightSoundsTests: XCTestCase {
    func testEligibilityGates() {
        XCTAssertTrue(DelightSounds.eligibility(enabled: true, reduceMotion: false, screenReader: false))
        XCTAssertFalse(DelightSounds.eligibility(enabled: false, reduceMotion: false, screenReader: false))
        XCTAssertFalse(DelightSounds.eligibility(enabled: true, reduceMotion: true, screenReader: false))
        XCTAssertFalse(DelightSounds.eligibility(enabled: true, reduceMotion: false, screenReader: true))
    }

    func testPlayMapsGestureToTone() {
        // The mapping itself is a pure lookup; the audio side is covered by
        // smoke (Task 8). This test locks which gestures produce sound.
        XCTAssertNotNil(DelightSounds.tone(for: .nod))
        XCTAssertNotNil(DelightSounds.tone(for: .hop))
        XCTAssertNotNil(DelightSounds.tone(for: .stretch))
        XCTAssertNotNil(DelightSounds.tone(for: .yawn))
        XCTAssertNil(DelightSounds.tone(for: .blink))
        XCTAssertNil(DelightSounds.tone(for: .none))
    }
}
