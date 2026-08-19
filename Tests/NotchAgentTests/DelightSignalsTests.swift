import XCTest
import AppKit
@testable import NotchAgent

final class DelightSignalsTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testDayKeyIsStable() {
        // 1_756_000_000 epoch = 2025-08-24T01:46:40Z.
        let date = Date(timeIntervalSince1970: 1_756_000_000)
        XCTAssertEqual(DelightSignals.dayKey(date, calendar: calendar), "2025-08-24")
    }

    func testCrossedMidnight() {
        let previous = Date(timeIntervalSince1970: 1_756_000_000)
        let sameDay = previous.addingTimeInterval(60)
        let nextDay = previous.addingTimeInterval(86_400)
        XCTAssertFalse(DelightSignals.crossedMidnight(previous: previous, now: sameDay, calendar: calendar))
        XCTAssertTrue(DelightSignals.crossedMidnight(previous: previous, now: nextDay, calendar: calendar))
    }

    func testQuotaResetDetectedOnBigJump() {
        // remaining = 100 - used: 5 → 80 is a reset-sized jump.
        XCTAssertTrue(DelightSignals.quotaResetDetected(
            previous: GaugeMetric(used: 95, isWeekly: false),
            current: GaugeMetric(used: 20, isWeekly: false)
        ))
        XCTAssertFalse(DelightSignals.quotaResetDetected(
            previous: GaugeMetric(used: 60, isWeekly: false),
            current: GaugeMetric(used: 40, isWeekly: false)
        ))
        XCTAssertFalse(DelightSignals.quotaResetDetected(previous: nil, current: nil))
    }

    func testTimeTintKeyframes() {
        func key(hour: Int) -> DelightSignals.TimeTintKey {
            let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: hour))!
            return DelightSignals.timeTint(at: date, calendar: calendar)
        }
        XCTAssertEqual(key(hour: 2), .night)
        XCTAssertEqual(key(hour: 4), .night)
        XCTAssertEqual(key(hour: 5), .dawn)
        XCTAssertEqual(key(hour: 8), .dawn)
        XCTAssertEqual(key(hour: 9), .day)
        XCTAssertEqual(key(hour: 16), .day)
        XCTAssertEqual(key(hour: 17), .dusk)
        XCTAssertEqual(key(hour: 19), .dusk)
        XCTAssertEqual(key(hour: 20), .night)
    }

    func testTintColorsDifferPerKey() {
        let colors = Set(DelightSignals.TimeTintKey.allCases.map { DelightSignals.tintColor(for: $0) })
        XCTAssertEqual(colors.count, DelightSignals.TimeTintKey.allCases.count)
    }
}
