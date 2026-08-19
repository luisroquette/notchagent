import XCTest
@testable import NotchAgent

/// The touch classifier: the SAME poke can be a gentle tap, a fast bump,
/// or a caress — the reaction must match the force. Everything here is
/// pure; the view feeds hover samples and reads the verdict.
final class TouchSenseTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func sample(_ x: Double, _ y: Double, at offset: Double) -> TouchSense.Sample {
        TouchSense.Sample(at: t0.addingTimeInterval(offset), x: x, y: y)
    }

    // MARK: Entry speed

    func testEntrySpeedZeroWhenStationary() {
        // A cursor that enters and stays put covers no ground.
        let samples = [
            sample(32, 20, at: 0),
            sample(32, 20, at: 0.05),
            sample(32, 20, at: 0.1),
            sample(32, 20, at: 0.15),
        ]
        XCTAssertEqual(TouchSense.entrySpeed(samples), 0, accuracy: 0.001)
    }

    func testEntrySpeedMeasuresDistanceOverTime() {
        // 10 samples, 6pt apart, 16ms cadence: 9 segments × 6pt = 54pt
        // over 0.144s ≈ 375pt/s.
        let samples = (0..<10).map {
            sample(32 + Double($0) * 6, 20, at: Double($0) * 0.016)
        }
        XCTAssertEqual(TouchSense.entrySpeed(samples), 375, accuracy: 10)
    }

    func testEntrySpeedNeedsAtLeastTwoSamples() {
        XCTAssertEqual(TouchSense.entrySpeed([sample(32, 20, at: 0)]), 0)
        XCTAssertEqual(TouchSense.entrySpeed([]), 0)
    }

    // MARK: Classification

    func testClassifyBumpAboveThreshold() {
        // Fast crossing: 48pt in 0.096s = 500pt/s — a bump.
        let samples = (0..<7).map {
            sample(8 + Double($0) * 8, 20, at: Double($0) * 0.016)
        }
        XCTAssertEqual(TouchSense.classify(samples), .bump)
    }

    func testClassifyTapBelowThreshold() {
        // A gentle approach: 12pt in 0.15s = 80pt/s — a tap.
        let samples = (0..<10).map {
            sample(20 + Double($0) * 1.33, 20, at: Double($0) * 0.0167)
        }
        XCTAssertEqual(TouchSense.classify(samples), .tap)
    }

    // MARK: Caress detection

    func testCaressCountsOscillationInHeadZone() {
        // A stroking motion on the head: 3 back-and-forth passes at
        // 10pt amplitude inside the head zone — reversals land well
        // above the 2 needed.
        let samples = (0..<25).map { i -> TouchSense.Sample in
            let t = Double(i) * 0.05
            return sample(32 + 10 * sin(t * 2 * .pi / 0.4), 15, at: t)
        }
        XCTAssertGreaterThanOrEqual(TouchSense.caressReversalCount(samples, headZoneMaxY: 32), 2)
        XCTAssertTrue(TouchSense.isCaress(samples, headZoneMaxY: 32))
    }

    func testCaressIgnoresBodyZone() {
        // The same oscillation down on the body is poking, not caressing.
        let samples = (0..<25).map { i -> TouchSense.Sample in
            let t = Double(i) * 0.05
            return sample(32 + 10 * sin(t * 2 * .pi / 0.4), 50, at: t)
        }
        XCTAssertFalse(TouchSense.isCaress(samples, headZoneMaxY: 32))
    }

    func testCaressIgnoresMicroJitter() {
        // 2pt hand jitter is not a stroke — the amplitude floor filters it.
        let samples = (0..<25).map { i -> TouchSense.Sample in
            let t = Double(i) * 0.05
            return sample(32 + 2 * sin(t * 2 * .pi / 0.4), 15, at: t)
        }
        XCTAssertFalse(TouchSense.isCaress(samples, headZoneMaxY: 32))
    }

    func testCaressIgnoresOneWayMotion() {
        // A single sweep, however long, has no reversals.
        let samples = (0..<25).map { i -> TouchSense.Sample in
            sample(8 + Double(i) * 2, 15, at: Double(i) * 0.05)
        }
        XCTAssertFalse(TouchSense.isCaress(samples, headZoneMaxY: 32))
    }

    func testCaressReversalsResetWhenLeavingHeadZone() {
        // Strokes on the head that dip down to the body break the stroke
        // — the reversal count restarts, it does not bridge zones.
        var samples: [TouchSense.Sample] = []
        samples.append(sample(22, 15, at: 0))     // head, left
        samples.append(sample(42, 15, at: 0.1))   // head, right (stroke 1)
        samples.append(sample(22, 50, at: 0.2))   // body dip — breaks
        samples.append(sample(42, 15, at: 0.3))   // head again (stroke 2)
        samples.append(sample(22, 15, at: 0.4))   // head left
        XCTAssertLessThan(TouchSense.caressReversalCount(samples, headZoneMaxY: 32), 2)
    }
}
