import XCTest
@testable import NotchAgent

final class PuppetMotionTests: XCTestCase {
    /// The visible thing is the TRANSITION between steps (the spring move),
    /// not the pose itself. A step may hold the previous pose (deliberate
    /// pause) or rest between hops — what can never happen is an invisible
    /// change.
    private func assertTransitionsVisible(_ steps: [MotionStep], _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        var previous = MotionStep.identity
        for (index, step) in steps.enumerated() {
            let moved = abs(step.offsetY - previous.offsetY) >= 4
                || abs(step.rotationDegrees - previous.rotationDegrees) >= 5
                || abs(step.scaleY - previous.scaleY) >= 0.09
            let samePose = step.scaleY == previous.scaleY
                && step.rotationDegrees == previous.rotationDegrees
                && step.offsetY == previous.offsetY
            if index == 0 {
                XCTAssertTrue(moved, "\(label) first step must move from rest", file: file, line: line)
            } else if samePose {
                // A deliberate hold of an already-visible pose (duration
                // differs; the pose is what matters).
            } else {
                XCTAssertTrue(moved, "\(label) step \(index) transitions invisibly", file: file, line: line)
            }
            previous = step
        }
    }

    func testBobVariantsAreVisibleVariedAndSettle() {
        XCTAssertEqual(BobVariant.allCases.count, 4, "the opening move needs variety")
        for variant in BobVariant.allCases {
            let steps = PuppetMotion.bobSteps(variant)
            XCTAssertGreaterThanOrEqual(steps.count, 4, "\(variant.rawValue) is too short to read as motion")
            assertTransitionsVisible(steps, variant.rawValue)
            // The settle step only needs the neutral POSE — its duration is
            // the breathing room before the next animation.
            let last = steps[steps.count - 1]
            XCTAssertEqual(last.scaleY, 1, "\(variant.rawValue) must settle back to rest")
            XCTAssertEqual(last.rotationDegrees, 0)
            XCTAssertEqual(last.offsetY, 0)
        }
    }

    func testPokeVariantsAreVisibleVariedAndSettle() {
        XCTAssertEqual(PokeVariant.allCases.count, 3, "the poke needs variety")
        for variant in PokeVariant.allCases {
            let steps = PuppetMotion.pokeSteps(variant)
            XCTAssertGreaterThanOrEqual(steps.count, 2)
            assertTransitionsVisible(steps, variant.rawValue)
            let last = steps[steps.count - 1]
            XCTAssertEqual(last.scaleY, 1, "\(variant.rawValue) must settle back to rest")
            XCTAssertEqual(last.rotationDegrees, 0)
            XCTAssertEqual(last.offsetY, 0)
        }
    }

    func testBlinkIntervalStaysIrregularAndInRange() {
        var rng = SplitMix64(seed: 7)
        var intervals: Set<Double> = []
        for _ in 0..<100 {
            let interval = PuppetMotion.blinkInterval(rng: &rng)
            XCTAssertGreaterThanOrEqual(interval, 2.5)
            XCTAssertLessThanOrEqual(interval, 5.5)
            intervals.insert((interval * 10).rounded())
        }
        XCTAssertGreaterThan(intervals.count, 5, "blinks must be irregular, not metronomic")
    }

    func testEyePositionsMatchAssetDerivation() {
        // Derived 19/08 from the four mascot PNGs (dark-cluster centers).
        XCTAssertEqual(PuppetMotion.eyeLeftRelative.x, 0.26, accuracy: 0.03)
        XCTAssertEqual(PuppetMotion.eyeRightRelative.x, 0.72, accuracy: 0.03)
        XCTAssertEqual(PuppetMotion.eyeLeftRelative.y, 0.35, accuracy: 0.03)
        XCTAssertEqual(PuppetMotion.eyeRightRelative.y, 0.35, accuracy: 0.03)
    }
}
