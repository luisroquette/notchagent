import XCTest
@testable import NotchAgent

final class MoonPhaseTests: XCTestCase {
    func testIlluminationStaysInRange() {
        for day in stride(from: 0, through: 60, by: 1) {
            let date = Date(timeIntervalSince1970: 1_756_000_000 + Double(day) * 86_400)
            let phase = MoonPhase.illumination(at: date)
            XCTAssertGreaterThanOrEqual(phase, 0)
            XCTAssertLessThan(phase, 1)
        }
    }

    func testSynodicPeriodRepeats() {
        // One synodic month later the phase returns.
        let a = Date(timeIntervalSince1970: 1_756_000_000)
        let b = a.addingTimeInterval(29.530588853 * 86_400)
        XCTAssertEqual(
            MoonPhase.illumination(at: a),
            MoonPhase.illumination(at: b),
            accuracy: 0.001
        )
    }

    func testHalfMonthFlipsIllumination() {
        // Half a synodic month = new → full (0 → 0.5).
        let newMoon = Date(timeIntervalSince1970: 1_756_000_000)
        let phase0 = MoonPhase.illumination(at: newMoon)
        let phaseHalf = MoonPhase.illumination(
            at: newMoon.addingTimeInterval(29.530588853 / 2 * 86_400)
        )
        let delta = abs(phaseHalf - phase0)
        XCTAssertEqual(delta, 0.5, accuracy: 0.01, "half a month must flip new↔full")
    }

    func testLitFractionBounds() {
        // Full-ish moon (phase ≈ 0.5) is ~fully lit; new moon (≈ 0) is dark.
        let reference = Date(timeIntervalSince1970: 1_756_000_000)
        let base = MoonPhase.illumination(at: reference)
        // Find the nearest full and new moon moments from the reference.
        let toFull = (0.5 - base).truncatingRemainder(dividingBy: 1)
        let fullDate = reference.addingTimeInterval(toFull * 29.530588853 * 86_400)
        XCTAssertGreaterThan(MoonPhase.litFraction(at: fullDate), 0.95)

        let toNew = (0 - base).truncatingRemainder(dividingBy: 1)
        let newDate = reference.addingTimeInterval(toNew * 29.530588853 * 86_400)
        XCTAssertLessThan(MoonPhase.litFraction(at: newDate), 0.05)
    }

    func testLabelBuckets() {
        let reference = Date(timeIntervalSince1970: 1_756_000_000)
        let base = MoonPhase.illumination(at: reference)
        func date(nearPhase target: Double) -> Date {
            let delta = (target - base).truncatingRemainder(dividingBy: 1)
            return reference.addingTimeInterval(delta * 29.530588853 * 86_400)
        }
        XCTAssertEqual(MoonPhase.label(at: date(nearPhase: 0.0)), .newMoon)
        XCTAssertEqual(MoonPhase.label(at: date(nearPhase: 0.25)), .firstQuarter)
        XCTAssertEqual(MoonPhase.label(at: date(nearPhase: 0.5)), .fullMoon)
        XCTAssertEqual(MoonPhase.label(at: date(nearPhase: 0.75)), .lastQuarter)
    }

    func testJulianDayMatchesKnownEpoch() {
        // 2000-01-01 12:00 UTC = JD 2451545.0 exactly.
        let known = Date(timeIntervalSince1970: 946_728_000)
        XCTAssertEqual(MoonPhase.julianDay(known), 2_451_545.0, accuracy: 0.0001)
    }
}
