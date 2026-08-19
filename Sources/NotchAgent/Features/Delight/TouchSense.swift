import Foundation

/// Classifies HOW the user touched the mascot from the raw hover trail —
/// the same poke can be a gentle tap, a fast bump, or a caress, and the
/// reaction must match the force. Pure functions: the view feeds
/// (position, timestamp) samples and reads the verdict. Nothing here
/// rolls dice — the trail IS the context.
public enum TouchSense {
    /// Average entry speed (pt/s) above which a touch is a bump.
    public static let bumpSpeedThreshold: Double = 400
    /// How long after hover entry the tap/bump verdict is read.
    public static let classificationWindow: TimeInterval = 0.15
    /// How far back the caress trail reaches.
    public static let caressWindow: TimeInterval = 1.4
    /// Direction reversals that make an oscillation a caress (three
    /// strokes: there, back, there).
    public static let caressReversalsNeeded: Int = 2
    /// Below this x-amplitude a reversal is cursor jitter, not a stroke.
    public static let caressMinStrokeAmplitude: Double = 6

    /// One hover frame: where the cursor was, and when.
    public struct Sample: Equatable, Sendable {
        public let at: Date
        public let x: Double
        public let y: Double

        public init(at: Date, x: Double, y: Double) {
            self.at = at
            self.x = x
            self.y = y
        }
    }

    /// The kind of touch: gentle tap or fast bump.
    public enum TouchKind: Equatable, Sendable {
        case tap
        case bump
    }

    /// Which edge the finger entered through — direction and speed
    /// together form the touch grammar: top+gentle is a caress,
    /// top+fast is a crush, bottom is a hop, corners are glances (slow)
    /// or annoyance (fast).
    public enum TouchZone: Equatable, Sendable {
        case top
        case bottom
        case side
        case center
    }

    /// The entry edge from the FIRST hover sample. Corners (the far
    /// horizontal thirds of the WIDTH) win over top and bottom — the
    /// corners have their own grammar. Vertical zones use the HEIGHT:
    /// in a 64×64 slot, side when |x − 32| > 16, top when y < 24,
    /// bottom when y > 40, center in between. Width and height are
    /// separate because real slots are not square (44×28 rows).
    public static func entryZone(
        _ sample: Sample,
        slotWidth: Double = 64,
        slotHeight: Double = 64
    ) -> TouchZone {
        let half = slotWidth / 2
        if abs(sample.x - half) > half / 2 { return .side }
        if sample.y < slotHeight * 0.375 { return .top }
        if sample.y > slotHeight * 0.625 { return .bottom }
        return .center
    }

    /// Total distance the trail covered, in points (sum of consecutive
    /// segment lengths).
    public static func trailLength(_ samples: [Sample]) -> Double {
        guard samples.count >= 2 else { return 0 }
        var length = 0.0
        for index in 1..<samples.count {
            let dx = samples[index].x - samples[index - 1].x
            let dy = samples[index].y - samples[index - 1].y
            length += (dx * dx + dy * dy).squareRoot()
        }
        return length
    }

    /// Average speed over the trail (pt/s): distance covered divided by
    /// the time it took.
    public static func entrySpeed(_ samples: [Sample]) -> Double {
        guard samples.count >= 2,
              let first = samples.first,
              let last = samples.last else { return 0 }
        let elapsed = last.at.timeIntervalSince(first.at)
        guard elapsed > 0.01 else { return 0 }
        return trailLength(samples) / elapsed
    }

    /// The verdict on entry: fast crossing = bump, everything else = tap.
    public static func classify(_ samples: [Sample]) -> TouchKind {
        entrySpeed(samples) >= bumpSpeedThreshold ? .bump : .tap
    }

    /// Counts direction reversals in the trail's x axis. A reversal
    /// counts only when the stroke between turns is at least
    /// `caressMinStrokeAmplitude` wide (else it is jitter) and the
    /// samples sit inside the head zone (y ≤ headZoneMaxY) — stroking
    /// the body is poking, not caressing. Leaving the head zone breaks
    /// the stroke: the counter restarts, it never bridges zones.
    public static func caressReversalCount(_ samples: [Sample], headZoneMaxY: Double) -> Int {
        guard let first = samples.first else { return 0 }
        var reversals = 0
        var strokeDirection = 0        // -1 leftward, +1 rightward, 0 undecided
        var extremeX = first.x         // most recent local extremum
        for sample in samples.dropFirst() {
            guard sample.y <= headZoneMaxY else {
                // Dipped out of the head zone: the stroke breaks.
                strokeDirection = 0
                extremeX = sample.x
                continue
            }
            let dx = sample.x - extremeX
            if strokeDirection == 0 {
                // Waiting for the first stroke wide enough to count.
                if dx >= caressMinStrokeAmplitude {
                    strokeDirection = 1
                    extremeX = sample.x
                } else if -dx >= caressMinStrokeAmplitude {
                    strokeDirection = -1
                    extremeX = sample.x
                }
            } else if strokeDirection == 1 {
                if dx > 0 {
                    extremeX = sample.x            // still extending right
                } else if -dx >= caressMinStrokeAmplitude {
                    reversals += 1                 // turned: right → left
                    strokeDirection = -1
                    extremeX = sample.x
                }
            } else {
                if dx < 0 {
                    extremeX = sample.x            // still extending left
                } else if dx >= caressMinStrokeAmplitude {
                    reversals += 1                 // turned: left → right
                    strokeDirection = 1
                    extremeX = sample.x
                }
            }
        }
        return reversals
    }

    /// The verdict on the ongoing trail: enough head-zone reversals to
    /// read as a caress.
    public static func isCaress(_ samples: [Sample], headZoneMaxY: Double) -> Bool {
        caressReversalCount(samples, headZoneMaxY: headZoneMaxY) >= caressReversalsNeeded
    }
}
