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
        XCTAssertEqual(BobVariant.allCases.count, 8, "the opening move needs variety")
        for variant in BobVariant.allCases {
            let steps = PuppetMotion.bobSteps(variant)
            // A bow is exactly 3 beats (lean, hold, rise) — three is the
            // floor; anything shorter cannot read as a gesture.
            XCTAssertGreaterThanOrEqual(steps.count, 3, "\(variant.rawValue) is too short to read as motion")
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

    func testSpriteRectPreservesAssetAspectInSquareSlot() {
        // REGRESSÃO 19/08: desenhar o asset 367×255 direto no slot quadrado
        // esticava o mascote na vertical — o retângulo deve ser letterbox.
        let rect = MascotPuppetView.spriteRect(
            imageSize: CGSize(width: 367, height: 255),
            canvasSize: CGSize(width: 64, height: 64)
        )
        XCTAssertEqual(rect.width, 64, accuracy: 0.01)
        XCTAssertEqual(rect.height, 64 * 255 / 367, accuracy: 0.01)
        XCTAssertEqual(rect.midY, 32, accuracy: 0.01, "centered vertically in the slot")
    }

    func testSpriteRectFillsWhenAspectMatches() {
        let rect = MascotPuppetView.spriteRect(
            imageSize: CGSize(width: 64, height: 64),
            canvasSize: CGSize(width: 64, height: 64)
        )
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 64, height: 64))
    }

    // MARK: easing profiles (fluidez por contexto)

    func testEaseEndpointsForAllProfiles() {
        for profile in EasingProfile.allCases {
            XCTAssertEqual(PuppetMotion.ease(0, profile: profile), 0, accuracy: 0.0001)
            XCTAssertEqual(PuppetMotion.ease(1, profile: profile), 1, accuracy: 0.0001)
        }
    }

    func testEasePersonalitiesOrder() {
        // A quarter of the way in: sharp covers the most ground, sluggish
        // the least (at 0.5 both smoothsteps coincide).
        let sharp = PuppetMotion.ease(0.25, profile: .sharp)
        let standard = PuppetMotion.ease(0.25, profile: .standard)
        let sluggish = PuppetMotion.ease(0.25, profile: .sluggish)
        XCTAssertGreaterThan(sharp, standard, "tense travel must be ahead")
        XCTAssertGreaterThan(standard, sluggish, "drowsy travel must drag")
    }

    func testElasticEaseOvershoots() {
        var maxEase = 0.0
        for i in 0...100 {
            maxEase = max(maxEase, PuppetMotion.ease(Double(i) / 100, profile: .elastic))
        }
        XCTAssertGreaterThan(maxEase, 1.05, "elastic must overshoot past the keyframe")
    }

    func testDurationScalePerContext() {
        XCTAssertGreaterThan(PuppetMotion.durationScale(for: .drowsy), 1, "drowsy drags")
        XCTAssertLessThan(PuppetMotion.durationScale(for: .tense), 1, "tense snaps")
        XCTAssertEqual(PuppetMotion.durationScale(for: .calm), 1, accuracy: 0.0001)
    }

    func testPoseRespectsDurationScale() {
        let steps = [MotionStep(offsetY: -10, duration: 1.0)]
        let slow = PuppetMotion.pose(
            steps: steps, start: t0, now: t0.addingTimeInterval(0.5), durationScale: 1.7
        )
        let normal = PuppetMotion.pose(
            steps: steps, start: t0, now: t0.addingTimeInterval(0.5), durationScale: 1.0
        )
        XCTAssertLessThan(abs(slow.offsetY), abs(normal.offsetY), "drowsy travel lags at the same instant")
    }

    func testPoseElasticOvershootsKeyframe() {
        let steps = [MotionStep(offsetY: -10, duration: 1.0)]
        var maxOffset = 0.0
        for i in 0...100 {
            let pose = PuppetMotion.pose(
                steps: steps, start: t0, now: t0.addingTimeInterval(Double(i) / 100), easing: .elastic
            )
            maxOffset = max(maxOffset, abs(pose.offsetY))
        }
        XCTAssertGreaterThan(maxOffset, 10.0, "elastic pose passes the keyframe then springs back")
    }

    func testCatalogEasingMapping() {
        XCTAssertEqual(DelightCatalog.easing(for: .tense), .sharp)
        XCTAssertEqual(DelightCatalog.easing(for: .poke), .sharp)
        XCTAssertEqual(DelightCatalog.easing(for: .drowsy), .sluggish)
        XCTAssertEqual(DelightCatalog.easing(for: .playful), .elastic)
        XCTAssertEqual(DelightCatalog.easing(for: .calm), .standard)
    }

    // MARK: anticipation + follow-through (staging)

    func testAnticipationMovesOppositeToTheFirstStep() {
        let step = MotionStep(offsetY: -10, duration: 0.25)
        let windUp = PuppetMotion.anticipationStep(for: step)
        XCTAssertGreaterThan(windUp.offsetY, 0, "the wind-up must load in the opposite direction")
        XCTAssertLessThan(abs(windUp.offsetY), abs(step.offsetY), "the wind-up is smaller than the move")

        let rotation = MotionStep(rotationDegrees: 10, duration: 0.25)
        let rotationWindUp = PuppetMotion.anticipationStep(for: rotation)
        XCTAssertLessThan(rotationWindUp.rotationDegrees, 0, "a rightward turn winds up leftward")
    }

    func testFollowThroughOvershootsPastRest() {
        let step = MotionStep(offsetY: -10, duration: 0.25)
        let tail = PuppetMotion.followThroughStep(for: step)
        XCTAssertGreaterThan(tail.offsetY, 0, "the tail continues past rest in the motion's direction")
        XCTAssertLessThan(abs(tail.offsetY), abs(step.offsetY), "the tail is smaller than the move")
    }

    func testStagedComposesAndStillSettles() {
        let steps = PuppetMotion.bobSteps(.hopBob)
        let staged = PuppetMotion.staged(steps, anticipation: true, followThrough: true)
        XCTAssertEqual(staged.count, steps.count + 3, "wind-up + tail + final rest")
        XCTAssertEqual(staged.first?.offsetY, PuppetMotion.anticipationStep(for: steps[0]).offsetY)
        // The last step is the final rest — the sequence always settles.
        let last = staged[staged.count - 1]
        XCTAssertEqual(last.scaleY, 1)
        XCTAssertEqual(last.rotationDegrees, 0)
        XCTAssertEqual(last.offsetY, 0)
    }

    func testStagedWithoutFlagsIsPassthrough() {
        let steps = PuppetMotion.bobSteps(.swingUpDown)
        XCTAssertEqual(PuppetMotion.staged(steps, anticipation: false, followThrough: false), steps)
    }

    func testCatalogStagingFlags() {
        XCTAssertTrue(DelightCatalog.anticipation(for: .playful), "playful winds up")
        XCTAssertTrue(DelightCatalog.anticipation(for: .greeting), "greetings wind up")
        XCTAssertFalse(DelightCatalog.anticipation(for: .tense), "tense has no time to wind up")
        XCTAssertFalse(DelightCatalog.anticipation(for: .drowsy), "drowsy has no energy to wind up")
        XCTAssertFalse(DelightCatalog.followThrough(for: .tense), "tense ends dead")
        XCTAssertTrue(DelightCatalog.followThrough(for: .calm))
    }

    // MARK: secondary motion (eyes + squash coupling)

    func testDerivedEyeStateBlinkAlwaysWins() {
        for context in MascotContext.allCases {
            XCTAssertEqual(
                PuppetMotion.derivedEyeState(context: context, poke: nil, elapsed: 0, blinking: true),
                .closed,
                "blink must override \(context.rawValue)"
            )
        }
    }

    func testDerivedEyeStateStartleWideThenAnnoyed() {
        XCTAssertEqual(
            PuppetMotion.derivedEyeState(context: .poke, poke: .startleJump, elapsed: 0.1, blinking: false),
            .wide
        )
        XCTAssertEqual(
            PuppetMotion.derivedEyeState(context: .poke, poke: .startleJump, elapsed: 0.4, blinking: false),
            .annoyed
        )
        XCTAssertEqual(
            PuppetMotion.derivedEyeState(context: .poke, poke: .annoyedWiggle, elapsed: 0.4, blinking: false),
            .annoyed
        )
    }

    func testDerivedEyeStateContexts() {
        XCTAssertEqual(PuppetMotion.derivedEyeState(context: .drowsy, poke: nil, elapsed: 0, blinking: false), .droopy)
        XCTAssertEqual(PuppetMotion.derivedEyeState(context: .midnightMoment, poke: nil, elapsed: 0, blinking: false), .droopy)
        XCTAssertEqual(PuppetMotion.derivedEyeState(context: .playful, poke: nil, elapsed: 0, blinking: false), .wide)
        XCTAssertEqual(PuppetMotion.derivedEyeState(context: .calm, poke: nil, elapsed: 0, blinking: false), .open)
        XCTAssertEqual(PuppetMotion.derivedEyeState(context: nil, poke: nil, elapsed: 0, blinking: false), .open)
    }

    func testMotionSquashIsNeutralWithoutSequence() {
        XCTAssertEqual(
            PuppetMotion.motionSquash(steps: [], start: nil, now: t0, easing: .standard, durationScale: 1),
            1,
            accuracy: 0.0001
        )
    }

    func testMotionSquashStaysBounded() {
        let steps = PuppetMotion.bobSteps(.hopBob)
        for i in 0...300 {
            let t = t0.addingTimeInterval(Double(i) / 100)
            let squash = PuppetMotion.motionSquash(
                steps: steps, start: t0, now: t, easing: .standard, durationScale: 1
            )
            XCTAssertGreaterThanOrEqual(squash, 0.94, "squash floor is -6%")
            XCTAssertLessThanOrEqual(squash, 1.06, "stretch ceiling is +6%")
        }
    }

    func testMotionSquashHasStretchAndSquashPhases() {
        // Across a hop the body must stretch in the air AND squash on
        // impact — both phases must exist.
        let steps = PuppetMotion.bobSteps(.hopBob)
        var maxSquash = 1.0
        var minSquash = 1.0
        for i in 0...400 {
            let t = t0.addingTimeInterval(Double(i) / 150)
            let squash = PuppetMotion.motionSquash(
                steps: steps, start: t0, now: t, easing: .standard, durationScale: 1
            )
            maxSquash = max(maxSquash, squash)
            minSquash = min(minSquash, squash)
        }
        XCTAssertGreaterThan(maxSquash, 1.005, "hops must stretch the body")
        XCTAssertLessThan(minSquash, 0.995, "landings must squash the body")
    }

    // MARK: runner revival (quota reset bounces the dino back)

    func testRevivalJumpArc() {
        XCTAssertEqual(NotchRunnerView.revivalJumpHeight(timeSinceRevival: -1), 0)
        XCTAssertEqual(NotchRunnerView.revivalJumpHeight(timeSinceRevival: 0), 0)
        XCTAssertEqual(NotchRunnerView.revivalJumpHeight(timeSinceRevival: 0.6), 10, accuracy: 0.01, "peak at mid-arc")
        XCTAssertEqual(NotchRunnerView.revivalJumpHeight(timeSinceRevival: 1.2), 0, accuracy: 0.01)
        XCTAssertEqual(NotchRunnerView.revivalJumpHeight(timeSinceRevival: 5), 0, "the bounce ends")
    }

    // MARK: context depth (celebration particles + compound yawn)

    func testCelebrationParticlesAreDeterministicAndArcUp() {
        let early = PuppetMotion.celebrationParticles(elapsed: 0.3)
        XCTAssertEqual(early.count, 12)
        XCTAssertEqual(early, PuppetMotion.celebrationParticles(elapsed: 0.3), "same instant, same particles")
        XCTAssertTrue(early.allSatisfy { $0.y < 0 }, "0.3s in, particles are still above the launch point")
        XCTAssertTrue(early.allSatisfy { abs($0.x) < 100 }, "the fan stays local")
        XCTAssertTrue(PuppetMotion.celebrationParticles(elapsed: 5).isEmpty, "the celebration ends")
        XCTAssertTrue(PuppetMotion.celebrationParticles(elapsed: -1).isEmpty)
    }

    func testYawnStretchInMidnightVocabulary() {
        XCTAssertTrue(
            DelightCatalog.bobVariants(for: .midnightMoment).contains(.yawnStretch),
            "midnight owns the compound yawn"
        )
    }

    // MARK: ambient presence (breathing + head turn)

    func testBreathingScaleBoundsAndPeriod() {
        // The breath runs on the continuous reference clock — its PHASE at
        // any anchor date is arbitrary. What must hold: the ±2% bounds,
        // the 3s period, and a full inhale/exhale sweep inside one cycle.
        let t0 = Date(timeIntervalSince1970: 1_756_000_000)
        var maxScale = 0.0
        var minScale = 2.0
        for i in 0...300 {
            let scale = PuppetMotion.breathingScale(now: t0.addingTimeInterval(Double(i) / 100))
            maxScale = max(maxScale, scale)
            minScale = min(minScale, scale)
            XCTAssertGreaterThanOrEqual(scale, 0.98)
            XCTAssertLessThanOrEqual(scale, 1.02)
        }
        XCTAssertGreaterThanOrEqual(maxScale, 1.019, "a cycle must reach the inhale peak")
        XCTAssertLessThanOrEqual(minScale, 0.981, "a cycle must reach the exhale trough")
        XCTAssertEqual(
            PuppetMotion.breathingScale(now: t0.addingTimeInterval(3)),
            PuppetMotion.breathingScale(now: t0),
            accuracy: 0.0001,
            "3s cycle repeats"
        )
    }

    func testHeadTurnFollowsCursorAndClamps() {
        XCTAssertEqual(PuppetMotion.headTurnRotation(cursorOffset: 0), 0)
        XCTAssertEqual(PuppetMotion.headTurnRotation(cursorOffset: 1), 4)
        XCTAssertEqual(PuppetMotion.headTurnRotation(cursorOffset: -1), -4, "cursor left turns left")
        XCTAssertEqual(PuppetMotion.headTurnRotation(cursorOffset: 0.5), 2)
        XCTAssertEqual(PuppetMotion.headTurnRotation(cursorOffset: 3), 4, "clamped")
        XCTAssertEqual(PuppetMotion.headTurnRotation(cursorOffset: -3), -4, "clamped")
    }

    // MARK: pose interpolation (the frame-by-frame driver)

    private let t0 = Date(timeIntervalSince1970: 1_756_000_000)

    func testPoseNilStartIsIdentity() {
        XCTAssertEqual(PuppetMotion.pose(steps: PuppetMotion.bobSteps(.swingUpDown), start: nil, now: t0), MotionStep.identity)
    }

    func testPoseAtStartIsRest() {
        // Keyframes are TARGETS: the sequence ramps from rest toward the
        // first step, so at t=0 the pose is still identity.
        let steps = PuppetMotion.bobSteps(.swingUpDown)
        XCTAssertEqual(PuppetMotion.pose(steps: steps, start: t0, now: t0), MotionStep.identity)
        let nearEnd = PuppetMotion.pose(steps: steps, start: t0, now: t0.addingTimeInterval(0.24))
        XCTAssertLessThan(nearEnd.offsetY, -6, "just before the first step ends, the pose is nearly there")
    }

    func testPoseMidStepInterpolates() {
        let steps = [MotionStep(offsetY: -10, duration: 1.0), MotionStep.identity]
        let mid = PuppetMotion.pose(steps: steps, start: t0, now: t0.addingTimeInterval(0.5))
        XCTAssertEqual(mid.offsetY, -5, accuracy: 0.01, "halfway through a 1s step, the pose is the midpoint")
    }

    func testPoseAfterSequenceSettlesToIdentity() {
        let steps = PuppetMotion.bobSteps(.hopBob)
        let total = steps.reduce(0) { $0 + $1.duration }
        let after = PuppetMotion.pose(steps: steps, start: t0, now: t0.addingTimeInterval(total + 1))
        XCTAssertEqual(after, MotionStep.identity)
    }

    func testPoseNeverJumpsBetweenSteps() {
        // Sampling every 16ms across a whole sequence: no adjacent pair may
        // differ by more than a small bound (no teleporting between keys).
        let steps = PuppetMotion.bobSteps(.wobbleFall)
        let total = steps.reduce(0) { $0 + $1.duration }
        var previous = PuppetMotion.pose(steps: steps, start: t0, now: t0)
        var t = 0.0
        while t < total {
            t += 0.016
            let pose = PuppetMotion.pose(steps: steps, start: t0, now: t0.addingTimeInterval(t))
            let jump = max(
                abs(pose.offsetY - previous.offsetY),
                abs(pose.rotationDegrees - previous.rotationDegrees),
                abs(pose.scaleY - previous.scaleY)
            )
            XCTAssertLessThanOrEqual(jump, 3.0, "pose jumped \(jump) between frames at t=\(t)")
            previous = pose
        }
    }

    // MARK: Ground shadow (the one depth cue in a flat 2D slot)

    func testShadowFullAtRest() {
        // On the ground the shadow is at full size and full strength.
        XCTAssertEqual(PuppetMotion.shadowScale(offsetY: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(PuppetMotion.shadowOpacity(offsetY: 0), 0.35, accuracy: 0.0001)
    }

    func testShadowShrinksAndFadesWithLift() {
        // Lifting (negative offsetY = up) shrinks the shadow and fades it —
        // the higher the mascot, the weaker its contact with the ground.
        let low = PuppetMotion.shadowScale(offsetY: -6)
        let high = PuppetMotion.shadowScale(offsetY: -14)
        XCTAssertLessThan(low, 1, "any lift must shrink the shadow")
        XCTAssertLessThan(high, low, "more lift must shrink it further")
        XCTAssertLessThan(PuppetMotion.shadowOpacity(offsetY: -14), PuppetMotion.shadowOpacity(offsetY: -6))
    }

    func testShadowClampsAtBothEnds() {
        // Sinking below the ground never grows the shadow past full; a
        // lift past the ceiling never shrinks it below its floor.
        XCTAssertEqual(PuppetMotion.shadowScale(offsetY: 10), 1, accuracy: 0.0001)
        let floored = PuppetMotion.shadowScale(offsetY: -40)
        XCTAssertEqual(floored, PuppetMotion.shadowScale(offsetY: -24), accuracy: 0.0001)
        XCTAssertGreaterThan(floored, 0.5, "the shadow must stay visible at any jump height")
        XCTAssertGreaterThan(PuppetMotion.shadowOpacity(offsetY: -40), 0.1)
    }

    func testShadowContinuousAcrossFlight() {
        // Sampling a full jump arc in small steps: no adjacent pair may
        // differ by more than a small bound — the shadow breathes, it
        // never teleports.
        var previous = PuppetMotion.shadowScale(offsetY: 0)
        var y = 0.0
        while y > -24 {
            y -= 0.5
            let scale = PuppetMotion.shadowScale(offsetY: y)
            XCTAssertLessThanOrEqual(abs(scale - previous), 0.02, "shadow jumped at lift \(y)")
            previous = scale
        }
    }
}
