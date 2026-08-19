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
        XCTAssertEqual(BobVariant.allCases.count, 9, "the opening move needs variety")
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
        XCTAssertGreaterThan(PuppetMotion.durationScale(for: .calm), 1, "calm lingers")
        XCTAssertEqual(PuppetMotion.durationScale(for: .poke), 1, accuracy: 0.0001, "pokes are always immediate")
    }

    func testPokeProfileIsSelfContained() {
        // The poke's travel personality must never inherit a previous
        // event's profile — a poke after a drowsy greeting is still a
        // snap, with no wind-up and a draining tail.
        XCTAssertEqual(DelightCatalog.easing(for: .poke), .sharp)
        XCTAssertEqual(DelightCatalog.anticipation(for: .poke), false)
        XCTAssertEqual(DelightCatalog.followThrough(for: .poke), true)
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

    // MARK: Interruption blend (a mid-gesture cut reads as a glitch)

    func testBlendStartsAtPreviousPose() {
        let previous = MotionStep(scaleY: 0.9, rotationDegrees: 12, offsetY: -8, duration: 0)
        let current = MotionStep(scaleY: 1.05, rotationDegrees: -4, offsetY: 2, duration: 0)
        let at = PuppetMotion.blendedPose(from: previous, to: current, switchedAt: t0, now: t0)
        XCTAssertEqual(at, previous, "the very first blend frame is exactly where the puppet was")
    }

    func testBlendConvergesToCurrentPose() {
        let previous = MotionStep(scaleY: 0.9, rotationDegrees: 12, offsetY: -8, duration: 0)
        let current = MotionStep(scaleY: 1.05, rotationDegrees: -4, offsetY: 2, duration: 0)
        let after = PuppetMotion.blendedPose(from: previous, to: current, switchedAt: t0, now: t0.addingTimeInterval(0.3))
        XCTAssertEqual(after, current, "after the blend window the new sequence owns the pose")
    }

    func testBlendMidpointInterpolatesLinearly() {
        let previous = MotionStep(scaleY: 0.8, rotationDegrees: 10, offsetY: -10, duration: 0)
        let current = MotionStep(scaleY: 1.0, rotationDegrees: 0, offsetY: 0, duration: 0)
        let mid = PuppetMotion.blendedPose(from: previous, to: current, switchedAt: t0, now: t0.addingTimeInterval(0.075))
        XCTAssertEqual(mid.scaleY, 0.9, accuracy: 0.01)
        XCTAssertEqual(mid.rotationDegrees, 5, accuracy: 0.01)
        XCTAssertEqual(mid.offsetY, -5, accuracy: 0.01)
    }

    func testBlendNeverOvershootsItsEndpoints() {
        // Every field stays between the two poses across the whole blend —
        // the crossfade is a bridge, never a bounce past either pose.
        let previous = MotionStep(scaleY: 1.08, rotationDegrees: -12, offsetY: -14, duration: 0)
        let current = MotionStep(scaleY: 0.9, rotationDegrees: 6, offsetY: 3, duration: 0)
        var t = 0.0
        while t <= 0.15 {
            let p = PuppetMotion.blendedPose(from: previous, to: current, switchedAt: t0, now: t0.addingTimeInterval(t))
            XCTAssertGreaterThanOrEqual(p.scaleY, min(previous.scaleY, current.scaleY) - 0.001)
            XCTAssertLessThanOrEqual(p.scaleY, max(previous.scaleY, current.scaleY) + 0.001)
            XCTAssertGreaterThanOrEqual(p.offsetY, min(previous.offsetY, current.offsetY) - 0.001)
            XCTAssertLessThanOrEqual(p.offsetY, max(previous.offsetY, current.offsetY) + 0.001)
            XCTAssertGreaterThanOrEqual(p.rotationDegrees, min(previous.rotationDegrees, current.rotationDegrees) - 0.001)
            XCTAssertLessThanOrEqual(p.rotationDegrees, max(previous.rotationDegrees, current.rotationDegrees) + 0.001)
            t += 0.005
        }
    }

    func testBlendWithoutSwitchReturnsCurrentPose() {
        let current = MotionStep(scaleY: 1.02, rotationDegrees: 3, offsetY: -4, duration: 0)
        let p = PuppetMotion.blendedPose(from: .identity, to: current, switchedAt: nil, now: t0)
        XCTAssertEqual(p, current, "no interruption = no blend layer")
    }

    // MARK: Directed poke (the reaction knows where the finger came from)

    func testPokeFromLeftLeansAwayToTheRight() {
        // pokeSide -1 = the poke came from the LEFT; the mascot flees the
        // finger, tilting to the RIGHT (positive = clockwise in canvas).
        let steps = PuppetMotion.directedPokeSteps(.startleJump, pokeSide: -1)
        XCTAssertGreaterThan(steps[0].rotationDegrees, 0, "a left poke must lean right")
    }

    func testPokeFromRightLeansAwayToTheLeft() {
        let steps = PuppetMotion.directedPokeSteps(.startleJump, pokeSide: 1)
        XCTAssertLessThan(steps[0].rotationDegrees, 0, "a right poke must lean left")
    }

    func testDirectedPokePreservesTheVariantBody() {
        // The lean is an opening move only — the rest of the poke plays
        // exactly as its undirected self.
        for variant in PokeVariant.allCases {
            let directed = PuppetMotion.directedPokeSteps(variant, pokeSide: -1)
            XCTAssertEqual(Array(directed.dropFirst()), PuppetMotion.pokeSteps(variant), "\(variant.rawValue) body must survive direction")
        }
    }

    func testDirectedPokeSettlesBackToRest() {
        let steps = PuppetMotion.directedPokeSteps(.annoyedWiggle, pokeSide: 1)
        XCTAssertEqual(steps.last?.scaleY, 1, "directed poke must settle to rest")
        XCTAssertEqual(steps.last?.rotationDegrees, 0)
        XCTAssertEqual(steps.last?.offsetY, 0)
    }

    func testPokeLeanReadsAsReactionNotFall() {
        // The lean must stay a reaction (≤ 10°) — past that it reads as
        // the mascot toppling over.
        for side: Double in [-1, 1] {
            let steps = PuppetMotion.directedPokeSteps(.shrinkSulk, pokeSide: side)
            XCTAssertLessThanOrEqual(abs(steps[0].rotationDegrees), 10, "lean of \(steps[0].rotationDegrees)° reads as a fall")
        }
    }

    // MARK: Touch intensity (the same poke, struck with force)

    func testPokeIntensityDefaultIsIdentity() {
        for variant in PokeVariant.allCases {
            XCTAssertEqual(
                PuppetMotion.pokeSteps(variant),
                PuppetMotion.pokeSteps(variant, intensity: 1),
                "\(variant.rawValue) at intensity 1 must be the original"
            )
        }
    }

    func testPokeIntensityScalesAmplitudes() {
        // A bump (1.6×) must read bigger than the gentle tap on the
        // combined amplitude of the pose — each variant uses different
        // fields (some only turn, some only lift), so the comparison is
        // over the sum of what each actually does.
        func amplitude(_ steps: [MotionStep]) -> Double {
            steps.map {
                abs($0.offsetY) + abs($0.rotationDegrees) + abs($0.scaleY - 1) * 20
            }.max() ?? 0
        }
        for variant in PokeVariant.allCases {
            let gentle = PuppetMotion.pokeSteps(variant)
            let forceful = PuppetMotion.pokeSteps(variant, intensity: 1.6)
            XCTAssertGreaterThan(
                amplitude(forceful),
                amplitude(gentle),
                "\(variant.rawValue) bump must strike harder"
            )
        }
    }

    func testPokeIntensityClampsExtremes() {
        // Even a ludicrous intensity stays a readable pose — no field
        // may blow past the clamp's physical bounds.
        let steps = PuppetMotion.pokeSteps(.startleJump, intensity: 10)
        for step in steps {
            XCTAssertLessThanOrEqual(abs(step.offsetY), 60, "offset exploded to \(step.offsetY)")
            XCTAssertLessThanOrEqual(abs(step.rotationDegrees), 60, "rotation exploded to \(step.rotationDegrees)")
            XCTAssertGreaterThan(step.scaleY, 0.3, "scale crushed to \(step.scaleY)")
        }
    }

    func testDirectedPokeLeanScalesWithIntensity() {
        // A bump from the side leans away harder than a gentle tap.
        let gentle = PuppetMotion.directedPokeSteps(.startleJump, pokeSide: -1)
        let forceful = PuppetMotion.directedPokeSteps(.startleJump, pokeSide: -1, intensity: 1.6)
        XCTAssertGreaterThan(
            abs(forceful[0].rotationDegrees),
            abs(gentle[0].rotationDegrees),
            "a bump's opening lean must beat a tap's"
        )
    }

    // MARK: Nuzzle (the caress the mascot likes)

    func testNuzzleSwaysGentlyAndSettles() {
        let steps = PuppetMotion.bobSteps(.nuzzle)
        XCTAssertGreaterThanOrEqual(steps.count, 3, "a nuzzle is too short to read as pleasure")
        XCTAssertEqual(steps.last?.scaleY, 1, "nuzzle must settle back to rest")
        XCTAssertEqual(steps.last?.rotationDegrees, 0)
        XCTAssertEqual(steps.last?.offsetY, 0)
    }

    func testNuzzleLeanFollowsTheCaressSide() {
        // The caress strokes one side — the mascot leans INTO it.
        let left = PuppetMotion.nuzzleSteps(lean: 6)
        let right = PuppetMotion.nuzzleSteps(lean: -6)
        XCTAssertEqual(left[0].rotationDegrees, 6, accuracy: 0.001)
        XCTAssertEqual(right[0].rotationDegrees, -6, accuracy: 0.001)
        XCTAssertEqual(left[0].scaleY, right[0].scaleY, "the swell does not depend on side")
    }

    func testNuzzleLeanClamps() {
        // A wild average position never twists the nuzzle past ±8°, and
        // a caress barely off-center still leans a visible ±5° — an
        // invisible answer would read as indifference.
        XCTAssertEqual(PuppetMotion.nuzzleSteps(lean: 20)[0].rotationDegrees, 8, accuracy: 0.001)
        XCTAssertEqual(PuppetMotion.nuzzleSteps(lean: -20)[0].rotationDegrees, -8, accuracy: 0.001)
        XCTAssertEqual(PuppetMotion.nuzzleSteps(lean: 2)[0].rotationDegrees, 5, accuracy: 0.001)
        XCTAssertEqual(PuppetMotion.nuzzleSteps(lean: -2)[0].rotationDegrees, -5, accuracy: 0.001)
    }

    // MARK: Crush (a hard finger pressing down from above)

    func testCrushStartsAtBasePose() {
        let base = MotionStep(scaleY: 0.9, rotationDegrees: 3, offsetY: -4, duration: 0)
        XCTAssertEqual(PuppetMotion.crushPose(base: base, elapsed: 0), base)
        XCTAssertEqual(PuppetMotion.crushPose(base: base, elapsed: -1), base, "before the crush there is no crush")
    }

    func testCrushDeepensMonotonicallyAndCaps() {
        // The longer the finger stays, the deeper the squash — until the
        // cap: a mascot can only be so flat.
        let base = MotionStep.identity
        let early = PuppetMotion.crushPose(base: base, elapsed: 0.2)
        let later = PuppetMotion.crushPose(base: base, elapsed: 0.8)
        let capped = PuppetMotion.crushPose(base: base, elapsed: 10)
        XCTAssertGreaterThan(later.offsetY, early.offsetY, "the crush deepens while the finger stays")
        XCTAssertLessThan(later.scaleY, early.scaleY, "the crush flattens while the finger stays")
        XCTAssertEqual(capped.offsetY, 5, accuracy: 0.001, "depth caps at 5pt")
        XCTAssertEqual(capped.scaleY, 0.88, accuracy: 0.001, "flattening caps at 12%")
    }

    func testCrushComposesWithAnActivePose() {
        // The crush rides on top of whatever pose is playing — it sinks
        // a shrinking sulk further without touching its rotation.
        let base = MotionStep(scaleY: 0.81, rotationDegrees: 9, offsetY: 8, duration: 0)
        let crushed = PuppetMotion.crushPose(base: base, elapsed: 0.5)
        XCTAssertGreaterThan(crushed.offsetY, base.offsetY)
        XCTAssertLessThan(crushed.scaleY, base.scaleY)
        XCTAssertEqual(crushed.rotationDegrees, base.rotationDegrees, "the crush never twists")
    }

    // MARK: Corner glance (being shown something at the corner)

    func testLookTurnsTowardTheCorner() {
        let left = PuppetMotion.lookSteps(direction: -1)
        let right = PuppetMotion.lookSteps(direction: 1)
        XCTAssertLessThan(left[0].rotationDegrees, 0, "a left-corner glance turns left")
        XCTAssertGreaterThan(right[0].rotationDegrees, 0, "a right-corner glance turns right")
        XCTAssertLessThanOrEqual(abs(left[0].rotationDegrees), 14, "the glance must not become a fall")
    }

    func testLookHoldsTheGazeAndSettles() {
        let steps = PuppetMotion.lookSteps(direction: 1)
        XCTAssertGreaterThanOrEqual(steps.count, 3, "glance, hold, return")
        XCTAssertEqual(steps[0].rotationDegrees, steps[1].rotationDegrees, "the gaze holds before returning")
        XCTAssertEqual(steps.last?.scaleY, 1)
        XCTAssertEqual(steps.last?.rotationDegrees, 0)
        XCTAssertEqual(steps.last?.offsetY, 0)
    }

    // MARK: Nuzzle eyes + shadow rect (lapidação L2)

    // REGRESSÃO: um poke depois de um carinho herdava o activeBob .nuzzle
    // residual e ficava de olhos fechados — a regra agora vive no estado
    // derivado, que só fecha os olhos quando o nuzzle REALMENTE toca.
    func testNuzzleClosesEyesOnlyWhileItPlays() {
        XCTAssertEqual(
            PuppetMotion.derivedEyeState(context: .calm, poke: nil, elapsed: 0, blinking: false, bob: .nuzzle),
            .closed,
            "a nuzzle closes the eyes in pleasure"
        )
        XCTAssertEqual(
            PuppetMotion.derivedEyeState(context: .poke, poke: .annoyedWiggle, elapsed: 0.5, blinking: false, bob: nil),
            .annoyed,
            "a poke after a caress keeps its annoyed eyes"
        )
        XCTAssertEqual(
            PuppetMotion.derivedEyeState(context: .calm, poke: nil, elapsed: 0, blinking: false, bob: .swingUpDown),
            .open,
            "any other gesture leaves the eyes open"
        )
    }

    // REGRESSÃO: no slot 44×28 da página de modelos o sprite letterboxado
    // encosta na borda do canvas e a sombra sangrava ~1pt para fora.
    func testShadowRectStaysInsideTightCanvas() {
        // 44×28 row: sprite rect fills the height, feet at the edge.
        let spriteRect = CGRect(x: 1.85, y: 0, width: 40.3, height: 28)
        let rect = PuppetMotion.shadowRect(spriteRect: spriteRect, canvasSize: CGSize(width: 44, height: 28), scale: 1)
        XCTAssertLessThanOrEqual(rect.maxY, 28, "shadow must not bleed past the canvas bottom")
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
    }

    func testShadowRectUnchangedInRoomierCanvas() {
        // The 64pt card keeps its original anchor: under the sprite's
        // feet, no clamp needed.
        let spriteRect = CGRect(x: 0, y: 9.8, width: 64, height: 44.4)
        let rect = PuppetMotion.shadowRect(spriteRect: spriteRect, canvasSize: CGSize(width: 64, height: 64), scale: 1)
        XCTAssertEqual(rect.minY, spriteRect.maxY - 1.5, accuracy: 0.001)
        XCTAssertLessThanOrEqual(rect.maxY, 64)
    }

    func testShadowRectShrinksWithLiftScale() {
        let spriteRect = CGRect(x: 0, y: 9.8, width: 64, height: 44.4)
        let full = PuppetMotion.shadowRect(spriteRect: spriteRect, canvasSize: CGSize(width: 64, height: 64), scale: 1)
        let lifted = PuppetMotion.shadowRect(spriteRect: spriteRect, canvasSize: CGSize(width: 64, height: 64), scale: 0.7)
        XCTAssertLessThan(lifted.width, full.width)
        XCTAssertEqual(lifted.midX, full.midX, accuracy: 0.001, "the shadow stays centered under the mascot")
    }
}
