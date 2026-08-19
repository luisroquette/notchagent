import AppKit
import SwiftUI

/// One keyframe of a mascot animation — the puppet plays a small sequence
/// of these. `.identity` is the settled pose.
public struct MotionStep: Equatable, Sendable {
    public var scaleY: Double
    public var rotationDegrees: Double
    public var offsetY: Double
    public var duration: Double

    public init(scaleY: Double = 1, rotationDegrees: Double = 0, offsetY: Double = 0, duration: Double) {
        self.scaleY = scaleY
        self.rotationDegrees = rotationDegrees
        self.offsetY = offsetY
        self.duration = duration
    }

    public static let identity = MotionStep(duration: 0)
}

/// Opening greetings: the mascot always moves when the panel opens, never
/// the same way twice.
public enum BobVariant: String, CaseIterable, Sendable {
    case swingUpDown, swayPendulum, wobbleFall, hopBob, bow, shiver, doubleTake, yawnStretch, nuzzle
}

/// Touch reactions: poking the mascot ALWAYS gets an annoyed response.
public enum PokeVariant: String, CaseIterable, Sendable {
    case startleJump, annoyedWiggle, shrinkSulk
}

public enum EyeState: Equatable {
    case open, closed, annoyed, wide, droopy
}

/// Velocity personality per context: how the pose travels between
/// keyframes. Same steps, different feel.
public enum EasingProfile: String, CaseIterable, Sendable {
    case standard, sharp, sluggish, elastic
}

public enum PuppetMotion {
    /// The real eye geometry of one mascot asset, MEASURED from the
    /// PNG pixels (dark-cluster bounding boxes, 19/08): centers and
    /// size relative to the sprite. The face overlay uses these to
    /// REPLACE the embedded eyes — a feature patch in body color covers
    /// the real eye box first, then the new expression draws on it.
    /// One eye or the other, never both.
    public struct EyeLayout: Equatable, Sendable {
        public let leftCenter: CGPoint
        public let rightCenter: CGPoint
        public let width: Double
        public let height: Double

        public init(leftCenter: CGPoint, rightCenter: CGPoint, width: Double, height: Double) {
            self.leftCenter = leftCenter
            self.rightCenter = rightCenter
            self.width = width
            self.height = height
        }
    }

    /// Measured eye layout per family. Haiku/Fable carry small dot eyes
    /// (~28×43px), Opus/Sonnet the big expressive ones (~45×59px).
    public static func eyeLayout(for spriteName: String) -> EyeLayout {
        switch spriteName {
        case "claude-fable":
            EyeLayout(leftCenter: CGPoint(x: 0.260, y: 0.347), rightCenter: CGPoint(x: 0.730, y: 0.347), width: 28.0 / 363.0, height: 43.0 / 255.0)
        case "claude-haiku":
            EyeLayout(leftCenter: CGPoint(x: 0.264, y: 0.347), rightCenter: CGPoint(x: 0.734, y: 0.347), width: 29.0 / 365.0, height: 43.0 / 255.0)
        case "claude-opus":
            EyeLayout(leftCenter: CGPoint(x: 0.286, y: 0.359), rightCenter: CGPoint(x: 0.712, y: 0.359), width: 45.0 / 366.0, height: 59.0 / 255.0)
        case "claude-sonnet":
            EyeLayout(leftCenter: CGPoint(x: 0.285, y: 0.359), rightCenter: CGPoint(x: 0.713, y: 0.359), width: 45.0 / 367.0, height: 59.0 / 255.0)
        default:
            EyeLayout(leftCenter: CGPoint(x: 0.274, y: 0.353), rightCenter: CGPoint(x: 0.722, y: 0.353), width: 37.0 / 365.0, height: 51.0 / 255.0)
        }
    }

    /// The face's body color between the eyes — sampled from all four
    /// assets (253, 110, 20). The replacement patch must match it or
    /// the patch itself would read as a third eye.
    public static let eyePatchColor = Color(
        red: 253.0 / 255.0,
        green: 110.0 / 255.0,
        blue: 20.0 / 255.0
    )

    /// A blink is a LID that drops and rises, not a state swap:
    /// 0 = open, 1 = fully closed, back to 0. Human-like timing: a
    /// quick drop (0.16s), a beat shut (0.04s), a slower rise (0.24s)
    /// — the rise is what makes a blink READ at mascot size. The view
    /// draws a body-color band of height `eyeHeight × amount` over the
    /// embedded eye, so the lid geometrically covers and uncovers it.
    public static func blinkAmount(elapsed: Double) -> Double {
        let down = 0.16
        let hold = 0.04
        let up = 0.24
        let total = down + hold + up
        guard elapsed >= 0, elapsed <= total else { return 0 }
        if elapsed < down {
            return ease(elapsed / down, profile: .standard)
        }
        if elapsed < down + hold {
            return 1
        }
        return ease(1 - (elapsed - down - hold) / up, profile: .standard)
    }

    /// Expression features breathe instead of snapping: opacity ramps
    /// 0→1 over the first `fade` seconds of the gesture and 1→0 over
    /// its last `fade` seconds, held at full in between. The embedded
    /// eye is covered gradually on the way in and revealed gradually
    /// on the way out.
    public static func expressionOpacity(elapsed: Double, total: Double, fade: Double = 0.15) -> Double {
        guard total > 0, elapsed >= 0 else { return 0 }
        if elapsed <= fade {
            return ease(elapsed / fade, profile: .standard)
        }
        if elapsed >= total - fade {
            return ease((total - elapsed) / fade, profile: .standard)
        }
        return 1
    }

    /// The start of the current half-second blink bucket — the clock
    /// grid the blink gate hashes.
    public static func blinkBucketStart(now: Date) -> Date {
        let t = now.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / 0.5).rounded(.down) * 0.5)
    }

    /// The blink schedule DERIVED from the clock: a deterministic hash
    /// of the current half-second bucket and the mascot's seed decides
    /// whether a blink starts in this bucket (~1 in 7 — a blink every
    /// ~3.5s on average, irregular in perception, and completely immune
    /// to view lifecycle: no Task, no state, nothing to kill). Same
    /// time + seed always gives the same answer.
    public static func blinkGate(now: Date, seed: UInt64) -> Bool {
        let bucket = UInt64(now.timeIntervalSinceReferenceDate * 2)
        var h = bucket &* 2_862_933_555_777_941_757 &+ seed &* 3_030_007_493
        h ^= h >> 32
        h &*= 0x9E37_79B9_7F4A_7C15
        return h % 7 == 0
    }

    /// Bob sequences: every variant swings the mascot like it's being
    /// rocked up and down (the wobbleFall one almost drops it), and every
    /// sequence settles back to identity.
    public static func bobSteps(_ variant: BobVariant) -> [MotionStep] {
        switch variant {
        case .swingUpDown: [
            MotionStep(offsetY: -10, duration: 0.25),
            MotionStep(offsetY: 8, duration: 0.25),
            MotionStep(offsetY: -6, duration: 0.25),
            MotionStep(offsetY: 4, duration: 0.25),
            MotionStep(duration: 0.35),
        ]
        case .swayPendulum: [
            MotionStep(rotationDegrees: -8, duration: 0.3),
            MotionStep(rotationDegrees: 8, duration: 0.3),
            MotionStep(rotationDegrees: -6, duration: 0.3),
            MotionStep(rotationDegrees: 6, duration: 0.3),
            MotionStep(duration: 0.35),
        ]
        case .wobbleFall: [
            MotionStep(rotationDegrees: 14, offsetY: 4, duration: 0.3),
            MotionStep(rotationDegrees: -10, duration: 0.25),
            MotionStep(rotationDegrees: 8, duration: 0.2),
            MotionStep(rotationDegrees: -6, duration: 0.2),
            MotionStep(duration: 0.45),
        ]
        case .hopBob: [
            MotionStep(offsetY: -12, duration: 0.2),
            MotionStep(duration: 0.15),
            MotionStep(offsetY: -8, duration: 0.2),
            MotionStep(duration: 0.15),
            MotionStep(offsetY: -4, duration: 0.2),
            MotionStep(duration: 0.3),
        ]
        case .bow: [
            // A little bow: lean forward and down, hold it, rise back.
            MotionStep(scaleY: 0.94, rotationDegrees: 14, duration: 0.35),
            MotionStep(scaleY: 0.94, rotationDegrees: 14, duration: 0.3),
            MotionStep(duration: 0.45),
        ]
        case .shiver: [
            // Nervous jitter: rapid tiny wiggles, then still. Amplitudes
            // sit just above the perception threshold — a shiver is small
            // but it must read.
            MotionStep(rotationDegrees: -5, duration: 0.07),
            MotionStep(rotationDegrees: 5, duration: 0.07),
            MotionStep(rotationDegrees: -5, duration: 0.07),
            MotionStep(rotationDegrees: 5, duration: 0.07),
            MotionStep(rotationDegrees: -5, duration: 0.07),
            MotionStep(rotationDegrees: 5, duration: 0.07),
            MotionStep(duration: 0.3),
        ]
        case .doubleTake: [
            // Glance away, snap back, glance the other way, settle.
            MotionStep(rotationDegrees: -10, duration: 0.18),
            MotionStep(duration: 0.12),
            MotionStep(rotationDegrees: 10, duration: 0.18),
            MotionStep(duration: 0.12),
            MotionStep(duration: 0.4),
        ]
        case .yawnStretch: [
            // Compound midnight yawn: stretch up, hold the stretch with a
            // drowsy lean (eyes go droopy via context, "z z z" floats up).
            MotionStep(scaleY: 1.06, rotationDegrees: -6, duration: 0.4),
            MotionStep(scaleY: 1.06, rotationDegrees: -6, duration: 0.5),
            MotionStep(duration: 0.5),
        ]
        case .nuzzle: [
            // The caress the mascot LIKES: a soft sway with a swell of
            // pleasure. Eyes close via the view; the opening lean toward
            // the caress side comes from `nuzzleSteps`.
            MotionStep(scaleY: 1.1, rotationDegrees: 7, duration: 0.3),
            MotionStep(scaleY: 1.1, rotationDegrees: -7, duration: 0.3),
            MotionStep(scaleY: 1.1, rotationDegrees: 6, duration: 0.25),
            MotionStep(duration: 0.4),
        ]
        }
    }

    /// The nuzzle with its directional opening: the mascot leans INTO
    /// the caress side first (positive = lean right). Capped at ±8° and
    /// floored at ±5° — below that the lean is invisible at slot size,
    /// and an invisible caress answer would read as indifference.
    public static func nuzzleSteps(lean: Double) -> [MotionStep] {
        var steps = bobSteps(.nuzzle)
        let clamped = min(max(lean, -8), 8)
        let visible = abs(clamped) < 5 ? (clamped < 0 ? -5 : 5) : clamped
        steps[0] = MotionStep(
            scaleY: steps[0].scaleY,
            rotationDegrees: visible,
            duration: steps[0].duration
        )
        return steps
    }

    /// A curious glance toward the corner being poked — like the finger
    /// is showing something. Turns up to ±12°, holds the gaze, returns.
    /// `direction`: -1 left corner, +1 right corner.
    public static func lookSteps(direction: Double) -> [MotionStep] {
        let turn = direction < 0 ? -12.0 : 12.0
        return [
            MotionStep(rotationDegrees: turn, offsetY: -2, duration: 0.25),
            MotionStep(rotationDegrees: turn, offsetY: -2, duration: 0.3),
            MotionStep(duration: 0.35),
        ]
    }

    /// A hard finger pressing down from above flattens the mascot while
    /// it stays: the pose sinks up to 5pt and shrinks up to 12% over
    /// ~0.8s, riding on top of whatever animation is playing. Releases
    /// the moment the finger lifts (the view stops feeding elapsed).
    public static func crushPose(base: MotionStep, elapsed: Double) -> MotionStep {
        guard elapsed > 0 else { return base }
        let depth = min(5, elapsed * 6)
        let shrink = min(0.12, elapsed * 0.1)
        return MotionStep(
            scaleY: base.scaleY * (1 - shrink),
            rotationDegrees: base.rotationDegrees,
            offsetY: base.offsetY + depth,
            duration: 0
        )
    }

    /// Poke sequences: startled, annoyed, sulking — all visibly "didn't
    /// like that", all settling back.
    public static func pokeSteps(_ variant: PokeVariant, intensity: Double = 1) -> [MotionStep] {
        let scaled = min(max(intensity, 0.3), 3)
        return basePokeSteps(variant).map { step in
            MotionStep(
                scaleY: 1 + (step.scaleY - 1) * scaled,
                rotationDegrees: step.rotationDegrees * scaled,
                offsetY: step.offsetY * scaled,
                duration: step.duration
            )
        }
    }

    /// The variant's raw steps at intensity 1 — the tap baseline.
    private static func basePokeSteps(_ variant: PokeVariant) -> [MotionStep] {
        switch variant {
        case .startleJump: [
            MotionStep(scaleY: 0.9, offsetY: -6, duration: 0.08),
            MotionStep(scaleY: 1.08, offsetY: -14, duration: 0.15),
            MotionStep(duration: 0.3),
        ]
        case .annoyedWiggle: [
            MotionStep(rotationDegrees: -12, duration: 0.12),
            MotionStep(rotationDegrees: 12, duration: 0.12),
            MotionStep(rotationDegrees: -12, duration: 0.12),
            MotionStep(rotationDegrees: 12, duration: 0.12),
            MotionStep(duration: 0.3),
        ]
        case .shrinkSulk: [
            MotionStep(scaleY: 0.88, offsetY: 5, duration: 0.15),
            MotionStep(scaleY: 0.88, offsetY: 5, duration: 0.45),
            MotionStep(duration: 0.35),
        ]
        }
    }

    /// The poke reaction knows WHERE the finger came from AND how hard it
    /// struck: it opens with a lean AWAY from the poke (a poke from the
    /// left — `pokeSide` -1 — tilts the mascot right, positive rotation
    /// in canvas space), then the variant's own body plays at the given
    /// intensity. A tap leans 9°, a bump leans harder.
    public static func directedPokeSteps(
        _ variant: PokeVariant,
        pokeSide: Double,
        intensity: Double = 1
    ) -> [MotionStep] {
        let lean = MotionStep(rotationDegrees: -pokeSide * 9 * intensity, duration: 0.1)
        return [lean] + pokeSteps(variant, intensity: intensity)
    }

    /// A stable per-identity seed (FNV-1a): the same name always yields
    /// the same seed, so each mascot's blink schedule stays its own and
    /// deterministic across launches.
    public static func stableSeed(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return hash
    }

    /// The pose at `now` for a sequence started at `start` — pure keyframe
    /// interpolation. nil start = identity. After the last step the pose
    /// holds identity (the sequence settled). `easing` gives the travel its
    /// personality; `durationScale` slows/speeds the whole sequence
    /// (drowsy drags, tense snaps).
    public static func pose(
        steps: [MotionStep],
        start: Date?,
        now: Date,
        easing: EasingProfile = .standard,
        durationScale: Double = 1
    ) -> MotionStep {
        guard let start, !steps.isEmpty else { return .identity }
        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= 0 else { return steps[0] }
        var accumulated: Double = 0
        var previous = MotionStep.identity
        for step in steps {
            let effectiveDuration = step.duration * durationScale
            let stepEnd = accumulated + effectiveDuration
            if elapsed < stepEnd {
                let f = effectiveDuration > 0
                    ? max(0, min(1, (elapsed - accumulated) / effectiveDuration))
                    : 1
                let eased = ease(f, profile: easing)
                return MotionStep(
                    scaleY: previous.scaleY + (step.scaleY - previous.scaleY) * eased,
                    rotationDegrees: previous.rotationDegrees + (step.rotationDegrees - previous.rotationDegrees) * eased,
                    offsetY: previous.offsetY + (step.offsetY - previous.offsetY) * eased,
                    duration: 0
                )
            }
            accumulated = stepEnd
            previous = step
        }
        return .identity
    }

    /// The travel personality: standard smoothstep, sharp (tense — most of
    /// the motion lands early), sluggish (drowsy — slowerstep, drags at
    /// both ends) and elastic (playful — overshoots past the keyframe and
    /// springs back).
    public static func ease(_ fraction: Double, profile: EasingProfile) -> Double {
        let t = min(max(fraction, 0), 1)
        switch profile {
        case .standard:
            return t * t * (3 - 2 * t)
        case .sharp:
            // Ease-out quadratic: most of the travel lands in the first
            // third — a snap, not a glide.
            return t * (2 - t)
        case .sluggish:
            return t * t * t * (t * (6 * t - 15) + 10)
        case .elastic:
            let c1 = 1.70158
            let c3 = c1 + 1
            return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
        }
    }

    /// How much slower/faster a context plays its steps — the same gesture
    /// has a mood: calm lingers, drowsy drags, tense snaps, playful bounces,
    /// and a poke is always immediate.
    public static func durationScale(for context: MascotContext) -> Double {
        switch context {
        case .drowsy, .midnightMoment: 1.7
        case .tense: 0.7
        case .calm: 1.15
        case .playful, .celebration: 0.9
        default: 1.0
        }
    }

    /// The wind-up: a small move in the OPPOSITE direction of the first
    /// real step — the pose preloads before committing. Deliberately small;
    /// it reads as intent, not as a separate gesture.
    public static func anticipationStep(for step: MotionStep) -> MotionStep {
        MotionStep(
            scaleY: step.scaleY == 1 ? 0.95 : 1 + (1 - step.scaleY) * 0.4,
            rotationDegrees: step.rotationDegrees != 0 ? -step.rotationDegrees * 0.35 : 0,
            offsetY: step.offsetY != 0 ? -step.offsetY * 0.35 : 0,
            duration: 0.12
        )
    }

    /// The tail: after settling, overshoot slightly PAST rest in the
    /// direction the gesture was going, then return — the motion never
    /// stops dead, it drains.
    public static func followThroughStep(for step: MotionStep) -> MotionStep {
        MotionStep(
            scaleY: step.scaleY == 1 ? 1.03 : 1 - (1 - step.scaleY) * 0.3,
            rotationDegrees: step.rotationDegrees != 0 ? -step.rotationDegrees * 0.25 : 0,
            offsetY: step.offsetY != 0 ? -step.offsetY * 0.25 : -1.5,
            duration: 0.18
        )
    }

    /// Composes the playable sequence: optional wind-up, the gesture, then
    /// the follow-through tail before the final rest.
    public static func staged(
        _ steps: [MotionStep],
        anticipation: Bool,
        followThrough: Bool
    ) -> [MotionStep] {
        var result: [MotionStep] = []
        if anticipation, let first = steps.first {
            result.append(anticipationStep(for: first))
        }
        result += steps
        if followThrough, let lastMoving = steps.dropLast().last ?? steps.first {
            result.append(followThroughStep(for: lastMoving))
            result.append(MotionStep(duration: 0.25))
        }
        return result
    }

    /// Squash/stretch coupled to the motion itself: the vertical velocity
    /// of the pose stretches the body in the air and squashes it on
    /// impact. Returns a scale multiplier around 1 (±6%).
    public static func motionSquash(
        steps: [MotionStep],
        start: Date?,
        now: Date,
        easing: EasingProfile,
        durationScale: Double
    ) -> Double {
        guard let start, !steps.isEmpty else { return 1 }
        let dt = 1.0 / 60.0
        let current = pose(steps: steps, start: start, now: now, easing: easing, durationScale: durationScale)
        let past = pose(steps: steps, start: start, now: now.addingTimeInterval(-dt), easing: easing, durationScale: durationScale)
        // Canvas y is down: moving UP is a negative delta — and moving up
        // stretches the body, so the sign flips.
        let dy = past.offsetY - current.offsetY
        let stretch = min(max(dy * 0.08, -0.06), 0.06)
        return 1 + stretch
    }

    /// Idle breathing: a slow ±2% vertical swell on a 3s cycle — the
    /// mascot is alive even when nothing is happening.
    public static func breathingScale(now: Date) -> Double {
        1 + 0.02 * sin(2 * .pi * now.timeIntervalSinceReferenceDate / 3.0)
    }

    /// One celebration pixel: position relative to the sprite's top-center
    /// (negative y = above the launch point), size and a palette index the
    /// view maps to the model colors.
    public struct CelebrationParticle: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let size: Double
        public let paletteIndex: Int

        public init(x: Double, y: Double, size: Double, paletteIndex: Int) {
            self.x = x
            self.y = y
            self.size = size
            self.paletteIndex = paletteIndex
        }
    }

    /// Deterministic confetti: 12 particles fan upward with per-index
    /// speed/size/color, pulled back down by gravity. Same elapsed → same
    /// particles; after 1.4s the celebration is over.
    public static func celebrationParticles(elapsed: Double) -> [CelebrationParticle] {
        guard elapsed >= 0, elapsed < 1.4 else { return [] }
        return (0..<12).map { index in
            let fan = (Double(index % 5) - 2) * 0.18
            let speed = 90.0 + Double(index % 4) * 22.0
            let vx = sin(fan) * speed
            let vy = -cos(fan) * speed
            let gravity = 260.0
            return CelebrationParticle(
                x: vx * elapsed,
                y: vy * elapsed + 0.5 * gravity * elapsed * elapsed,
                size: 2.0 + Double(index % 3),
                paletteIndex: index % 4
            )
        }
    }

    /// The idle head-turn: the mascot leans toward the cursor, up to ±4°.
    /// `cursorOffset` is -1…1 across the slot (negative = cursor left).
    public static func headTurnRotation(cursorOffset: Double) -> Double {
        min(max(cursorOffset, -1), 1) * 4
    }

    /// The ground shadow's size factor: lifting the sprite (negative
    /// offsetY = up) shrinks the contact patch — the depth cue that sells
    /// every jump. 0 = full size, floor at 0.6 of the size for a 24pt+
    /// lift (the highest any pose reaches is 14pt).
    public static func shadowScale(offsetY: Double) -> Double {
        let lift = min(max(-offsetY, 0), 24)
        return 1 - lift / 24 * 0.4
    }

    /// The ground shadow's strength: full contact at 0.35, fading to 0.20
    /// at the top of a jump — a higher mascot casts a lighter shadow.
    public static func shadowOpacity(offsetY: Double) -> Double {
        let lift = min(max(-offsetY, 0), 24)
        return 0.35 - lift / 24 * 0.15
    }

    /// The ground shadow's rect inside the canvas: shrinks with the lift
    /// scale, anchored under the sprite's feet, and clamped so it never
    /// bleeds past the canvas bottom — in tight slots (44×28 rows) the
    /// letterboxed sprite's feet sit at the canvas edge.
    public static func shadowRect(
        spriteRect: CGRect,
        canvasSize: CGSize,
        scale: Double
    ) -> CGRect {
        let height = max(1.5, spriteRect.height * 0.09 * scale)
        return CGRect(
            x: spriteRect.midX - spriteRect.width * 0.30 * scale,
            y: min(spriteRect.maxY - 1.5, canvasSize.height - height),
            width: spriteRect.width * 0.60 * scale,
            height: height
        )
    }

    /// Clamps the pose's vertical travel to the canvas: a mascot inside
    /// a frame must not jump out of it. The lift is bounded by the space
    /// above the sprite, the sink by the space below — tight slots
    /// (44×28 rows) allow neither, the 64pt card allows ~10pt each way.
    public static func clampedLift(
        offsetY: Double,
        spriteRect: CGRect,
        canvasSize: CGSize
    ) -> Double {
        let up = max(offsetY, -spriteRect.minY)
        return min(up, canvasSize.height - spriteRect.maxY)
    }

    /// Clamps the rendered vertical scale: the layer scales from the
    /// sprite's feet, so swelling past the canvas clips a whole band off
    /// the top. Shrinking never clips — it only needs a floor. Tight
    /// rows cap at 1.0: no swell (the lean and eyes still carry the
    /// gesture), but no clip either.
    public static func clampedScaleY(
        scaleY: Double,
        spriteRect: CGRect,
        canvasSize: CGSize
    ) -> Double {
        let maxScale = canvasSize.height / max(spriteRect.height, 1)
        return min(max(scaleY, 0.4), maxScale)
    }

    /// Interruption blend: when a new gesture cuts an in-flight one
    /// (a poke mid-bob, an alert mid-hop), the puppet crossfades over
    /// `blendDuration` from where it was to where the new sequence says
    /// it should be. A cut reads as a glitch; a bridge reads as intent.
    /// nil `switchedAt` = no interruption happened — return `current`.
    public static func blendedPose(
        from previous: MotionStep,
        to current: MotionStep,
        switchedAt: Date?,
        now: Date,
        blendDuration: Double = 0.15
    ) -> MotionStep {
        guard let switchedAt else { return current }
        let elapsed = now.timeIntervalSince(switchedAt)
        guard elapsed >= 0, elapsed < blendDuration else { return current }
        let f = elapsed / blendDuration
        return MotionStep(
            scaleY: previous.scaleY + (current.scaleY - previous.scaleY) * f,
            rotationDegrees: previous.rotationDegrees + (current.rotationDegrees - previous.rotationDegrees) * f,
            offsetY: previous.offsetY + (current.offsetY - previous.offsetY) * f,
            duration: 0
        )
    }

    /// The eyes are DERIVED, not stored: blink always wins, a nuzzle
    /// closes them in pleasure, a startle opens wide before settling
    /// into annoyance, drowsy contexts wear heavy lids, excited
    /// contexts open wide.
    public static func derivedEyeState(
        context: MascotContext?,
        poke: PokeVariant?,
        elapsed: Double,
        blinking: Bool,
        bob: BobVariant? = nil
    ) -> EyeState {
        if blinking { return .closed }
        if bob == .nuzzle { return .closed }
        if let poke {
            switch poke {
            case .startleJump: return elapsed < 0.25 ? .wide : .annoyed
            case .annoyedWiggle, .shrinkSulk: return .annoyed
            }
        }
        if let context {
            if context == .drowsy || context == .midnightMoment { return .droopy }
            if context == .playful || context == .celebration { return .wide }
        }
        return .open
    }
}

/// The living mascot: rocks when the panel opens (varied), always reacts
/// to a poke with displeasure, and blinks constantly. Self-contained —
/// local state only, no engine dependency.
///
/// EVERYTHING renders inside one Canvas, driven by TimelineView(.periodic)
/// at 30fps — the update schedule this panel window provably renders (the
/// weather clock uses it). View transform modifiers (rotationEffect/
/// scaleEffect/offset) and display-link-driven schedules
/// (TimelineView(.animation), withAnimation springs) do NOT render in this
/// panel — the hardcoded-tilt probe proved the modifiers inert — while
/// Canvas drawing with explicit context transforms does.
public struct MascotPuppetView: View {
    public let spriteName: String
    /// Whether this mascot plays the mind's contextual requests (bobs on
    /// expand, celebrations…). Non-reactive mascots keep their ambient
    /// presence (breathing, blink, head-turn) and their own poke, but they
    /// never act out global events — only the active model's mascot does.
    public let reactive: Bool
    /// The slot's real size. The touch grammar derives from it — zones,
    /// sides, head zone, gaze tracking. ProviderCardView uses the 64×64
    /// default; the models page rows pass 44×28.
    public let slotSize: CGSize
    private let pokeCooldown: TimeInterval = 2
    /// Shorter than the poke's: a tap may flow into a caress almost
    /// immediately — felt the touch, recognized the affection.
    private let caressCooldown: TimeInterval = 0.8

    /// This mascot's own blink seed — a stable hash of its sprite name,
    /// so the mascots on screen never blink in chorus.
    private var blinkSeed: UInt64 { PuppetMotion.stableSeed(spriteName) }

    private var slotHalfX: Double { slotSize.width / 2 }
    /// The head band: above this y a touch is "on top", below it "on the
    /// body" (caresses need the head; the crush releases past the top).
    private var headZoneTopY: Double { slotSize.height * 0.375 }
    /// The caress zone: the upper half of the slot.
    private var headZoneMaxY: Double { slotSize.height / 2 }

    @State private var steps: [MotionStep] = []
    @State private var animationStart: Date?
    @State private var isBusy = false
    @State private var lastPokeAt = Date.distantPast
    @State private var playedRequestID = 0
    @State private var easing: EasingProfile = .standard
    @State private var durationScale: Double = 1
    @State private var useAnticipation = false
    @State private var useFollowThrough = false
    @State private var activeContext: MascotContext?
    @State private var activePoke: PokeVariant?
    @State private var activeBob: BobVariant?
    @State private var cursorOffset: Double = 0
    @State private var pokeCursor = 0
    @State private var wasHovering = false
    // Touch sensing: the hover trail feeds the classifier — the first
    // ~150ms decide tap vs bump, the ongoing trail watches for caresses.
    @State private var entrySamples: [TouchSense.Sample] = []
    @State private var caressSamples: [TouchSense.Sample] = []
    @State private var entryAt: Date?
    @State private var lastCaressAt = Date.distantPast
    /// While a hard finger stays on top, the crush keeps deepening —
    /// nil when the finger lifts or leaves the head zone.
    @State private var crushingSince: Date?
    /// The sprite, loaded once per view: the canvas redraws 30×/s and
    /// must never touch the disk per frame.
    @State private var loadedSprite: NSImage?
    // Interruption blend: the pose where the last gesture was cut and
    // when — the new sequence crossfades in from there instead of
    // snapping.
    @State private var interruptedPose: MotionStep = .identity
    @State private var switchedAt: Date?
    // Sequence generation: stale finish tasks from an interrupted
    // gesture must not clear the one playing now.
    @State private var generation = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(MascotMind.self) private var mind

    public init(
        spriteName: String,
        reactive: Bool = true,
        slotSize: CGSize = CGSize(width: 64, height: 64)
    ) {
        self.spriteName = spriteName
        self.reactive = reactive
        self.slotSize = slotSize
    }

    private var spriteImage: NSImage? { loadedSprite }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            // The pose as drawn: blend layer first, crush on top. The
            // crush is timeline-driven — a perfectly still finger keeps
            // sinking it to the cap; only the release (hover .ended or
            // leaving the head zone) lifts it.
            let pose = renderedPose(now: timeline.date)
            Canvas { context, size in
                // Aspect-preserving sprite rect, centered — the assets are
                // wide (367×255); drawing into the square slot stretches
                // them vertically.
                let spriteRect = Self.spriteRect(imageSize: spriteImage?.size, canvasSize: size)
                // The rendered lift, clamped to the canvas: the mascot
                // never jumps out of its frame (tight rows allow no
                // vertical travel). Shadow and sprite both use it, so
                // the contact stays physically honest.
                let lift = PuppetMotion.clampedLift(
                    offsetY: pose.offsetY,
                    spriteRect: spriteRect,
                    canvasSize: size
                )
                // Ground shadow first, under the sprite layer: it shrinks
                // and fades as the mascot lifts, and never follows the
                // pose's rotation — contact lives on the ground.
                let shadowScale = PuppetMotion.shadowScale(offsetY: lift)
                let shadowRect = PuppetMotion.shadowRect(
                    spriteRect: spriteRect,
                    canvasSize: size,
                    scale: shadowScale
                )
                context.fill(
                    Path(ellipseIn: shadowRect),
                    with: .color(Color.black.opacity(PuppetMotion.shadowOpacity(offsetY: lift)))
                )
                context.drawLayer { layer in
                    // Squash/stretch coupled to the motion: stretch in the
                    // air, squash on impact — volume-preserving.
                    let squash = PuppetMotion.motionSquash(
                        steps: steps, start: animationStart, now: timeline.date,
                        easing: easing, durationScale: durationScale
                    )
                    // Ambient presence, idle only: slow breathing and the
                    // head leaning toward the cursor. Animations own the
                    // pose while they play.
                    let idle = steps.isEmpty
                    let breathing = idle && !reduceMotion
                        ? PuppetMotion.breathingScale(now: timeline.date)
                        : 1
                    let headTurn = idle && !reduceMotion
                        ? PuppetMotion.headTurnRotation(cursorOffset: cursorOffset)
                        : 0
                    // Anchor at the sprite's bottom-center: translate,
                    // scale, rotate, translate back, then the clamped
                    // lift (canvas y is down, so negative lifts).
                    layer.translateBy(x: spriteRect.midX, y: spriteRect.maxY)
                    layer.scaleBy(x: pow(squash, -0.5), y: PuppetMotion.clampedScaleY(
                        scaleY: pose.scaleY * squash * breathing,
                        spriteRect: spriteRect,
                        canvasSize: size
                    ))
                    layer.rotate(by: .degrees(pose.rotationDegrees + headTurn))
                    layer.translateBy(x: -spriteRect.midX, y: -spriteRect.maxY)
                    layer.translateBy(x: 0, y: lift)

                    if let image = spriteImage {
                        layer.draw(
                            Image(nsImage: image).resizable().interpolation(.none),
                            in: spriteRect
                        )
                    } else {
                        layer.fill(
                            Path(spriteRect),
                            with: .color(Theme.coral.opacity(0.4))
                        )
                    }
                    let gestureElapsed = animationStart.map { timeline.date.timeIntervalSince($0) } ?? 0
                    // The blink gate is DERIVED from the clock — no
                    // Task, no state, nothing a view lifecycle can kill
                    // (a Task-bound blink died with every view recycle;
                    // this one cannot).
                    let bucketStart = PuppetMotion.blinkBucketStart(now: timeline.date)
                    let blink = !reduceMotion && PuppetMotion.blinkGate(now: timeline.date, seed: blinkSeed)
                        ? PuppetMotion.blinkAmount(elapsed: timeline.date.timeIntervalSince(bucketStart))
                        : 0
                    let eyes = PuppetMotion.derivedEyeState(
                        context: activeContext,
                        poke: activePoke,
                        elapsed: gestureElapsed,
                        blinking: blink > 0,
                        // A nuzzle closes the eyes — pleasure, not alarm.
                        bob: animationStart != nil ? activeBob : nil
                    )
                    // Features breathe in and out with the gesture; the
                    // blink is geometric (the lid itself carries it).
                    let totalDuration = steps.reduce(0) { $0 + $1.duration } * durationScale
                    let featureOpacity = PuppetMotion.expressionOpacity(
                        elapsed: gestureElapsed,
                        total: totalDuration
                    )
                    drawFace(
                        state: eyes,
                        blinkProgress: blink,
                        opacity: featureOpacity,
                        context: layer,
                        rect: spriteRect
                    )
                }
                drawContextExtras(context: context, size: size, spriteRect: spriteRect, now: timeline.date)
            }
        }
        .onAppear {
            // A recycled view (panel re-expand) must not believe the
            // cursor is still inside — the next entry reseeds the touch
            // trail and any leftover crush releases.
            wasHovering = false
            entryAt = nil
            entrySamples = []
            caressSamples = []
            crushingSince = nil
            if loadedSprite == nil,
               let url = Bundle.main.url(forResource: "Mascots/\(spriteName)", withExtension: "png") {
                loadedSprite = NSImage(contentsOf: url)
            }
            guard !reduceMotion else { return }
            // The expand already published a contextual request; play it.
            play(mind.animationRequest)
        }
        .onChange(of: mind.animationRequest) { _, request in
            play(request)
        }
        .onContinuousHover { phase in
            // The head follows the cursor while it's over the mascot;
            // leaving the slot resets the gaze. The whole trail feeds the
            // touch classifier: the first ~150ms decide tap vs bump, and
            // the ongoing trail watches for caresses on the head.
            switch phase {
            case .active(let location):
                cursorOffset = min(max((location.x - slotHalfX) / slotHalfX, -1), 1)
                let now = Date()
                let sample = TouchSense.Sample(at: now, x: location.x, y: location.y)
                if !wasHovering {
                    wasHovering = true
                    entrySamples = [sample]
                    caressSamples = [sample]
                    entryAt = now
                } else {
                    // The entry trail only feeds the classifier's window —
                    // past it, the samples have nothing to measure and
                    // must not accumulate for the rest of the hover.
                    if entryAt != nil {
                        entrySamples.append(sample)
                    }
                    if let entry = entryAt,
                       now.timeIntervalSince(entry) >= TouchSense.classificationWindow {
                        entryAt = nil
                        finishTouch(samples: entrySamples)
                    }
                    // Caress watch: keep only the recent window, and if
                    // the trail reads as stroking the head, react to it.
                    caressSamples.append(sample)
                    caressSamples.removeAll { now.timeIntervalSince($0.at) > TouchSense.caressWindow }
                    if TouchSense.isCaress(caressSamples, headZoneMaxY: headZoneMaxY) {
                        triggerCaress(samples: caressSamples)
                        caressSamples = []
                    }
                    // The finger lifted off the head: the crush releases.
                    if crushingSince != nil, location.y >= headZoneTopY {
                        crushingSince = nil
                    }
                }
            case .ended:
                // A bump that crosses and leaves inside the window still
                // gets classified — the short trail already proves speed.
                if entryAt != nil {
                    finishTouch(samples: entrySamples)
                }
                wasHovering = false
                cursorOffset = 0
                entryAt = nil
                entrySamples = []
                caressSamples = []
                crushingSince = nil
            }
        }
    }

    /// The classification window closed: read the touch grammar — WHERE
    /// the finger entered (zone) and HOW fast (kind) — and react. The
    /// average entry x says which side the finger came from.
    private func finishTouch(samples: [TouchSense.Sample]) {
        guard let first = samples.first else { return }
        let kind = TouchSense.classify(samples)
        let zone = TouchSense.entryZone(
            first,
            slotWidth: slotSize.width,
            slotHeight: slotSize.height
        )
        let averageX = samples.map(\.x).reduce(0, +) / Double(max(samples.count, 1))
        let fromLeft = averageX < slotHalfX
        switch zone {
        case .top:
            // Over the head: gentle closes the eyes like a puppy getting
            // a caress; fast keeps crushing while the finger stays.
            if kind == .bump {
                triggerCrush(fromLeft: fromLeft)
            } else {
                triggerCaress(samples: samples)
            }
        case .bottom:
            // From below: a little hop — higher when the finger comes fast.
            triggerHop(kind: kind, fromLeft: fromLeft)
        case .side:
            // The corners: a slow poke glances toward what the finger is
            // showing; a fast one is an annoying jab.
            if kind == .bump {
                triggerPoke(kind: kind, fromLeft: fromLeft, forcedVariant: .annoyedWiggle)
            } else {
                triggerLook(direction: fromLeft ? -1 : 1)
            }
        case .center:
            triggerPoke(kind: kind, fromLeft: fromLeft)
        }
    }

    /// A poke ALWAYS gets an annoyed reaction, and the reaction knows
    /// WHERE it came from AND how hard it struck — a gentle tap plays the
    /// variant at full force, a bump plays it at 1.6×. Personal: local
    /// round-robin, this mascot only, unless the zone's grammar demands
    /// a specific variant.
    private func triggerPoke(
        kind: TouchSense.TouchKind,
        fromLeft: Bool,
        forcedVariant: PokeVariant? = nil
    ) {
        guard !reduceMotion else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPokeAt) >= pokeCooldown else { return }
        lastPokeAt = now
        var cursor = pokeCursor
        let variant = forcedVariant ?? DelightCatalog.selectPoke(cursor: &cursor)
        if forcedVariant == nil { pokeCursor = cursor }
        // The poke owns its travel personality — a poke right after a
        // drowsy greeting is still a snap, never the greeting's sluggish
        // leftovers.
        easing = DelightCatalog.easing(for: .poke)
        durationScale = PuppetMotion.durationScale(for: .poke)
        useAnticipation = DelightCatalog.anticipation(for: .poke)
        useFollowThrough = DelightCatalog.followThrough(for: .poke)
        activeContext = .poke
        activePoke = variant
        // A poke after a caress must not inherit the nuzzle's closed
        // eyes — the poke owns its expression.
        activeBob = nil
        play(
            poke: variant,
            pokeSide: fromLeft ? -1 : 1,
            intensity: kind == .bump ? 1.6 : 1
        )
    }

    /// A finger coming up from below: the mascot hops — a gentle little
    /// hop for a slow approach, a full jump when the finger comes fast.
    /// Playful, never annoyed: the eyes stay wide, not angry.
    private func triggerHop(kind: TouchSense.TouchKind, fromLeft: Bool) {
        guard !reduceMotion else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPokeAt) >= pokeCooldown else { return }
        lastPokeAt = now
        easing = DelightCatalog.easing(for: .playful)
        durationScale = PuppetMotion.durationScale(for: .playful)
        useAnticipation = DelightCatalog.anticipation(for: .playful)
        useFollowThrough = DelightCatalog.followThrough(for: .playful)
        activeContext = .playful
        activePoke = nil
        activeBob = nil
        play(
            poke: .startleJump,
            pokeSide: fromLeft ? -1 : 1,
            intensity: kind == .bump ? 1.6 : 0.6
        )
    }

    /// A hard finger from above: the shrink-sulk strike at 1.6×, and the
    /// continuous crush begins — while the finger stays on top, the
    /// mascot keeps sinking and flattening.
    private func triggerCrush(fromLeft: Bool) {
        guard !reduceMotion else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPokeAt) >= pokeCooldown else { return }
        lastPokeAt = now
        easing = DelightCatalog.easing(for: .poke)
        durationScale = PuppetMotion.durationScale(for: .poke)
        useAnticipation = DelightCatalog.anticipation(for: .poke)
        useFollowThrough = DelightCatalog.followThrough(for: .poke)
        activeContext = .poke
        activePoke = .shrinkSulk
        activeBob = nil
        play(poke: .shrinkSulk, pokeSide: fromLeft ? -1 : 1, intensity: 1.6)
        crushingSince = now
    }

    /// A slow poke at the corner: the mascot glances toward it, eyes
    /// wide with curiosity — like the finger is showing something.
    private func triggerLook(direction: Double) {
        guard !reduceMotion else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCaressAt) >= caressCooldown else { return }
        lastCaressAt = now
        easing = .standard
        durationScale = 1
        useAnticipation = false
        useFollowThrough = true
        activeContext = .playful
        activePoke = nil
        activeBob = nil
        begin(sequence: PuppetMotion.staged(
            PuppetMotion.lookSteps(direction: direction),
            anticipation: false,
            followThrough: true
        ))
    }

    /// A caress is the one touch the mascot LIKES: eyes close (via the
    /// derived eye state), the body swells a little and leans into the
    /// side being stroked. Its own cooldown lets a tap flow into a
    /// caress: felt the touch, recognized the affection, leaned in.
    private func triggerCaress(samples: [TouchSense.Sample]) {
        guard !reduceMotion else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCaressAt) >= caressCooldown else { return }
        lastCaressAt = now
        let averageX = samples.map(\.x).reduce(0, +) / Double(max(samples.count, 1))
        let lean = (averageX - slotHalfX) / slotHalfX * 8
        easing = DelightCatalog.easing(for: .calm)
        durationScale = PuppetMotion.durationScale(for: .calm)
        useAnticipation = false
        useFollowThrough = true
        activeContext = .calm
        activePoke = nil
        activeBob = .nuzzle
        begin(sequence: PuppetMotion.staged(
            PuppetMotion.nuzzleSteps(lean: lean),
            anticipation: false,
            followThrough: true
        ))
    }

    /// The pose as drawn at `now`: the interruption blend first, then the
    /// crush on top — one function, so `begin` captures the same pose the
    /// canvas renders (a blend starting mid-crush never snaps).
    private func renderedPose(now: Date) -> MotionStep {
        let base = reduceMotion
            ? MotionStep.identity
            : PuppetMotion.blendedPose(
                from: interruptedPose,
                to: PuppetMotion.pose(
                    steps: steps,
                    start: animationStart,
                    now: now,
                    easing: easing,
                    durationScale: durationScale
                ),
                switchedAt: switchedAt,
                now: now
            )
        return crushingSince.map {
            PuppetMotion.crushPose(base: base, elapsed: now.timeIntervalSince($0))
        } ?? base
    }

    /// Plays a published request: contextual bob or poke, skipping replays
    /// of an id the puppet already performed. The request's context sets
    /// the travel personality (easing + duration scale). Non-reactive
    /// mascots only act on their own pokes — global events belong to the
    /// active model's mascot.
    private func play(_ request: AnimationRequest?) {
        guard let request, request.id > playedRequestID, !reduceMotion else { return }
        guard request.poke == nil || reactive else { return }
        playedRequestID = request.id
        easing = DelightCatalog.easing(for: request.context)
        durationScale = PuppetMotion.durationScale(for: request.context)
        useAnticipation = DelightCatalog.anticipation(for: request.context)
        useFollowThrough = DelightCatalog.followThrough(for: request.context)
        activeContext = request.context
        activePoke = request.poke
        activeBob = request.bob
        if let bob = request.bob {
            play(bob: bob)
        } else if let poke = request.poke {
            play(poke: poke)
        }
    }

    /// Aspect-preserving, centered rect for the sprite inside the slot —
    /// the assets are wider than tall, so a square slot letterboxes them.
    static func spriteRect(imageSize: CGSize?, canvasSize: CGSize) -> CGRect {
        guard let imageSize, imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: canvasSize)
        }
        let aspect = imageSize.width / imageSize.height
        let canvasAspect = canvasSize.width / canvasSize.height
        if aspect > canvasAspect {
            let height = canvasSize.width / aspect
            return CGRect(
                x: 0,
                y: (canvasSize.height - height) / 2,
                width: canvasSize.width,
                height: height
            )
        } else {
            let width = canvasSize.height * aspect
            return CGRect(
                x: (canvasSize.width - width) / 2,
                y: 0,
                width: width,
                height: canvasSize.height
            )
        }
    }

    /// Canvas-space extras that do NOT follow the sprite's pose: the
    /// celebration confetti and the midnight "z z z".
    private func drawContextExtras(
        context: GraphicsContext,
        size: CGSize,
        spriteRect: CGRect,
        now: Date
    ) {
        if activeContext == .celebration, let start = animationStart {
            let elapsed = now.timeIntervalSince(start)
            let palette: [Color] = [Theme.modelHaiku, Theme.modelSonnet, Theme.modelOpus, Theme.modelFable]
            for particle in PuppetMotion.celebrationParticles(elapsed: elapsed) {
                let rect = CGRect(
                    x: spriteRect.midX + particle.x,
                    y: spriteRect.minY + particle.y,
                    width: particle.size,
                    height: particle.size
                )
                context.fill(Path(rect), with: .color(palette[particle.paletteIndex].opacity(0.9)))
            }
        }
        if activeBob == .yawnStretch, activeContext == .midnightMoment, let start = animationStart {
            let elapsed = now.timeIntervalSince(start)
            if elapsed > 0.4, elapsed < 1.2 {
                context.draw(
                    Text("z z z").font(Theme.body(8, weight: .bold)).foregroundStyle(Theme.textDim),
                    at: CGPoint(x: spriteRect.maxX - 8, y: spriteRect.minY - 4 - (elapsed - 0.4) * 6)
                )
            }
        }
    }

    /// The face overlay at the asset's MEASURED eye positions, drawn
    /// inside the sprite's layer so it follows every pose. The embedded
    /// eyes ARE the open state — every other expression REPLACES them:
    /// the blink is a GEOMETRIC lid (a body-color band of height
    /// `eyeHeight × blinkProgress` descends over the embedded eye and
    /// rises again), and the features fade in/out with the gesture via
    /// `opacity` — the embedded eye is covered gradually, never swapped.
    private func drawFace(
        state: EyeState,
        blinkProgress: Double,
        opacity: Double,
        context: GraphicsContext,
        rect: CGRect
    ) {
        guard state != .open else { return }
        let layout = PuppetMotion.eyeLayout(for: spriteName)
        let ink = Color.black.opacity(0.88)
        let patch = PuppetMotion.eyePatchColor

        func point(_ rel: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + rel.x * rect.width, y: rect.minY + rel.y * rect.height)
        }

        let centers = [point(layout.leftCenter), point(layout.rightCenter)]
        let eyeWidth = layout.width * rect.width
        let eyeHeight = layout.height * rect.height

        for center in centers {
            let eyeRect = CGRect(
                x: center.x - eyeWidth / 2,
                y: center.y - eyeHeight / 2,
                width: eyeWidth,
                height: eyeHeight
            )
            if state == .closed {
                // The descending lid: a body-color band grows from the
                // top of the eye box — the embedded eye is covered and
                // uncovered geometrically, no opacity involved.
                let lidHeight = eyeHeight * min(max(blinkProgress, 0), 1)
                if lidHeight > 0 {
                    context.fill(
                        Path(CGRect(
                            x: eyeRect.minX,
                            y: eyeRect.minY,
                            width: eyeRect.width,
                            height: lidHeight
                        )),
                        with: .color(patch)
                    )
                }
                continue
            }
            // Replacement patch rides a FASTER fade than the feature:
            // a half-transparent patch would let the embedded eye ghost
            // through it — the old 'two eyes' bug in translucent form.
            // The patch lands in ~60ms; the feature breathes at its own
            // pace.
            context.fill(Path(eyeRect), with: .color(patch.opacity(min(opacity * 2.5, 1))))

            switch state {
            case .annoyed:
                // Slanted "unimpressed" brows: \ / inside the eye box.
                var strokes = Path()
                strokes.move(to: CGPoint(x: center.x - eyeWidth * 0.5, y: center.y + eyeHeight * 0.45))
                strokes.addLine(to: CGPoint(x: center.x + eyeWidth * 0.5, y: center.y - eyeHeight * 0.45))
                context.stroke(strokes, with: .color(ink.opacity(opacity)), lineWidth: max(1.5, eyeHeight * 0.1))
            case .wide:
                // Startled: the eye blows up past its own box.
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - eyeWidth * 0.55,
                        y: center.y - eyeHeight * 0.5,
                        width: eyeWidth * 1.1,
                        height: eyeHeight
                    )),
                    with: .color(ink.opacity(opacity))
                )
            case .droopy:
                // Heavy lids: a half-height eye with a lid band on top.
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - eyeWidth * 0.5,
                        y: center.y - eyeHeight * 0.2,
                        width: eyeWidth,
                        height: eyeHeight * 0.55
                    )),
                    with: .color(ink.opacity(opacity))
                )
                var lid = Path()
                lid.move(to: CGPoint(x: center.x - eyeWidth * 0.55, y: center.y - eyeHeight * 0.3))
                lid.addLine(to: CGPoint(x: center.x + eyeWidth * 0.55, y: center.y - eyeHeight * 0.3))
                context.stroke(lid, with: .color(ink.opacity(opacity)), lineWidth: max(1.5, eyeHeight * 0.1))
            case .closed, .open:
                break
            }
        }
    }

    private func play(bob variant: BobVariant) {
        begin(sequence: PuppetMotion.staged(
            PuppetMotion.bobSteps(variant),
            anticipation: useAnticipation,
            followThrough: useFollowThrough
        ))
    }

    private func play(poke variant: PokeVariant, pokeSide: Double = 0, intensity: Double = 1) {
        let steps = pokeSide != 0
            ? PuppetMotion.directedPokeSteps(variant, pokeSide: pokeSide, intensity: intensity)
            : PuppetMotion.pokeSteps(variant, intensity: intensity)
        begin(sequence: PuppetMotion.staged(
            steps,
            anticipation: useAnticipation,
            followThrough: useFollowThrough
        ))
    }

    /// Starts a sequence. If another gesture was in flight, captures the
    /// RENDERED pose at the cut (blend and crush included) and crossfades
    /// the new sequence in from there — interruptions read as intent,
    /// never as a teleport.
    private func begin(sequence: [MotionStep]) {
        if animationStart != nil || !steps.isEmpty || crushingSince != nil {
            interruptedPose = renderedPose(now: Date())
            switchedAt = Date()
        }
        generation += 1
        steps = sequence
        animationStart = Date()
        isBusy = true
        scheduleFinish(after: sequence, scaledBy: durationScale, generation: generation) {
            self.activeContext = nil
            self.activePoke = nil
        }
    }

    /// Releases the busy flag once the sequence's scaled duration passed —
    /// the pose itself returns to identity purely (see `pose`). A stale
    /// finish from an interrupted gesture must NOT clear the one playing
    /// now: it checks its generation first.
    private func scheduleFinish(
        after sequence: [MotionStep],
        scaledBy scale: Double = 1,
        generation: Int,
        onFinish: (() -> Void)? = nil
    ) {
        let total = sequence.reduce(0) { $0 + $1.duration } * scale
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(total))
            guard generation == self.generation else { return }
            isBusy = false
            steps = []
            animationStart = nil
            switchedAt = nil
            onFinish?()
        }
    }
}
