import XCTest
@testable import NotchAgent

final class SolarPhaseTests: XCTestCase {
    // Fixed "today": sunrise 06:20, sunset 17:55 (São Paulo winter).
    private let sunrise = Date(timeIntervalSince1970: 1_756_088_400) // 2026-08-18 06:20 UTC-3
    private let sunset = Date(timeIntervalSince1970: 1_756_130_100)  // 2026-08-18 17:55 UTC-3

    func testNightBeforeDawnWindow() {
        let now = sunrise.addingTimeInterval(-45 * 60)
        XCTAssertEqual(SolarPhase.at(now: now, sunrise: sunrise, sunset: sunset, isDay: false).phase, .night)
    }

    func testDawnAtSunriseMomentIsHalfway() {
        let phase = SolarPhase.at(now: sunrise, sunrise: sunrise, sunset: sunset, isDay: true)
        XCTAssertEqual(phase.phase, .dawn)
        XCTAssertEqual(phase.transition, 0.5, accuracy: 0.001)
    }

    func testDawnStartAndEnd() {
        let start = SolarPhase.at(now: sunrise.addingTimeInterval(-30 * 60), sunrise: sunrise, sunset: sunset, isDay: true)
        XCTAssertEqual(start.phase, .dawn)
        XCTAssertEqual(start.transition, 0, accuracy: 0.001)

        // Window is [start, end): one minute before the edge is still dawn,
        // the exact edge has already become day (transition 1 = over).
        let end = SolarPhase.at(now: sunrise.addingTimeInterval(29 * 60), sunrise: sunrise, sunset: sunset, isDay: true)
        XCTAssertEqual(end.phase, .dawn)
        XCTAssertEqual(end.transition, 59.0 / 60.0, accuracy: 0.001)
    }

    func testMiddayIsDay() {
        let noon = sunrise.addingTimeInterval(6 * 3600)
        XCTAssertEqual(SolarPhase.at(now: noon, sunrise: sunrise, sunset: sunset, isDay: true).phase, .day)
    }

    func testDuskAtSunsetMomentIsHalfway() {
        let phase = SolarPhase.at(now: sunset, sunrise: sunrise, sunset: sunset, isDay: true)
        XCTAssertEqual(phase.phase, .dusk)
        XCTAssertEqual(phase.transition, 0.5, accuracy: 0.001)
    }

    func testNightAfterDuskWindow() {
        let now = sunset.addingTimeInterval(45 * 60)
        XCTAssertEqual(SolarPhase.at(now: now, sunrise: sunrise, sunset: sunset, isDay: false).phase, .night)
    }

    func testMissingSunTimesFallBackToIsDay() {
        XCTAssertEqual(SolarPhase.at(now: sunrise, sunrise: nil, sunset: nil, isDay: true).phase, .day)
        XCTAssertEqual(SolarPhase.at(now: sunset, sunrise: nil, sunset: sunset, isDay: false).phase, .night)
    }
}
