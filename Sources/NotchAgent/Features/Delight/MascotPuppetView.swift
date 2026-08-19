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
    case swingUpDown, swayPendulum, wobbleFall, hopBob, bow, shiver, doubleTake
}

/// Touch reactions: poking the mascot ALWAYS gets an annoyed response.
public enum PokeVariant: String, CaseIterable, Sendable {
    case startleJump, annoyedWiggle, shrinkSulk
}

public enum EyeState: Equatable {
    case open, closed, annoyed
}

/// Velocity personality per context: how the pose travels between
/// keyframes. Same steps, different feel.
public enum EasingProfile: String, CaseIterable, Sendable {
    case standard, sharp, sluggish, elastic
}

public enum PuppetMotion {
    /// Eye centers relative to the sprite size — derived from the four
    /// mascot assets (same face layout in all families ≈ 0.26/0.72 x,
    /// 0.35 y). The face overlay draws on top of these points.
    public static let eyeLeftRelative = CGPoint(x: 0.26, y: 0.35)
    public static let eyeRightRelative = CGPoint(x: 0.72, y: 0.35)

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
        }
    }

    /// Poke sequences: startled, annoyed, sulking — all visibly "didn't
    /// like that", all settling back.
    public static func pokeSteps(_ variant: PokeVariant) -> [MotionStep] {
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

    /// Always-on blinking: a blink every 2.5–5.5s, irregular on purpose.
    public static func blinkInterval(rng: inout some RandomNumberGenerator) -> Double {
        Double.random(in: 2.5...5.5, using: &rng)
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

    /// How much slower/faster a context plays its steps.
    public static func durationScale(for context: MascotContext) -> Double {
        switch context {
        case .drowsy, .midnightMoment: 1.7
        case .tense: 0.7
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
    private let pokeCooldown: TimeInterval = 2

    @State private var steps: [MotionStep] = []
    @State private var animationStart: Date?
    @State private var eyeState: EyeState = .open
    @State private var isBusy = false
    @State private var lastPokeAt = Date.distantPast
    @State private var playedRequestID = 0
    @State private var easing: EasingProfile = .standard
    @State private var durationScale: Double = 1
    @State private var useAnticipation = false
    @State private var useFollowThrough = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(MascotMind.self) private var mind

    public init(spriteName: String) {
        self.spriteName = spriteName
    }

    private var spriteImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "Mascots/\(spriteName)", withExtension: "png")
        else { return nil }
        return NSImage(contentsOf: url)
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            let pose = reduceMotion
                ? MotionStep.identity
                : PuppetMotion.pose(
                    steps: steps,
                    start: animationStart,
                    now: timeline.date,
                    easing: easing,
                    durationScale: durationScale
                )
            Canvas { context, size in
                context.drawLayer { layer in
                    // Aspect-preserving sprite rect, centered — the assets
                    // are wide (367×255); drawing into the square slot
                    // stretches them vertically.
                    let spriteRect = Self.spriteRect(imageSize: spriteImage?.size, canvasSize: size)
                    // Anchor at the sprite's bottom-center: translate,
                    // scale, rotate, translate back, then the pose offset
                    // (canvas y is down, so a negative offsetY lifts).
                    layer.translateBy(x: spriteRect.midX, y: spriteRect.maxY)
                    layer.scaleBy(x: pose.scaleY, y: pose.scaleY)
                    layer.rotate(by: .degrees(pose.rotationDegrees))
                    layer.translateBy(x: -spriteRect.midX, y: -spriteRect.maxY)
                    layer.translateBy(x: 0, y: pose.offsetY)

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
                    drawFace(state: eyeState, context: layer, rect: spriteRect)
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            startBlinking()
            // The expand already published a contextual request; play it.
            play(mind.animationRequest)
        }
        .onChange(of: mind.animationRequest) { _, request in
            play(request)
        }
        .onHover { hovering in
            guard hovering, !reduceMotion else { return }
            let now = Date()
            guard now.timeIntervalSince(lastPokeAt) >= pokeCooldown else { return }
            lastPokeAt = now
            mind.notePoked()
        }
    }

    /// Plays a published request: contextual bob or poke, skipping replays
    /// of an id the puppet already performed. The request's context sets
    /// the travel personality (easing + duration scale).
    private func play(_ request: AnimationRequest?) {
        guard let request, request.id > playedRequestID, !reduceMotion else { return }
        playedRequestID = request.id
        easing = DelightCatalog.easing(for: request.context)
        durationScale = PuppetMotion.durationScale(for: request.context)
        useAnticipation = DelightCatalog.anticipation(for: request.context)
        useFollowThrough = DelightCatalog.followThrough(for: request.context)
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

    /// The pixel-art face at the asset's real eye positions — drawn inside
    /// the sprite's layer so it follows every pose.
    private func drawFace(state: EyeState, context: GraphicsContext, rect: CGRect) {
        let eyeWidth = max(2, rect.width * 0.07)
        let eyeHeight = eyeWidth * 1.1
        let color = Color.black.opacity(0.88)

        func point(_ rel: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + rel.x * rect.width, y: rect.minY + rel.y * rect.height)
        }

        let left = point(PuppetMotion.eyeLeftRelative)
        let right = point(PuppetMotion.eyeRightRelative)

        switch state {
        case .open:
            context.fill(
                Path(ellipseIn: CGRect(
                    x: left.x - eyeWidth / 2, y: left.y - eyeHeight / 2,
                    width: eyeWidth, height: eyeHeight
                )),
                with: .color(color)
            )
            context.fill(
                Path(ellipseIn: CGRect(
                    x: right.x - eyeWidth / 2, y: right.y - eyeHeight / 2,
                    width: eyeWidth, height: eyeHeight
                )),
                with: .color(color)
            )
        case .closed:
            // Thick enough to cover the sprite's baked-in eyes.
            let lineHeight = max(2, rect.height * 0.02)
            context.fill(
                Path(CGRect(
                    x: left.x - eyeWidth * 0.7, y: left.y - lineHeight / 2,
                    width: eyeWidth * 1.4, height: lineHeight
                )),
                with: .color(color)
            )
            context.fill(
                Path(CGRect(
                    x: right.x - eyeWidth * 0.7, y: right.y - lineHeight / 2,
                    width: eyeWidth * 1.4, height: lineHeight
                )),
                with: .color(color)
            )
        case .annoyed:
            // Slanted "unimpressed" brows: \ / over both eyes.
            var strokes = Path()
            for eye in [left, right] {
                strokes.move(to: CGPoint(x: eye.x - eyeWidth * 0.8, y: eye.y + eyeHeight * 0.6))
                strokes.addLine(to: CGPoint(x: eye.x + eyeWidth * 0.8, y: eye.y - eyeHeight * 0.6))
            }
            context.stroke(strokes, with: .color(color), lineWidth: max(1.5, rect.height * 0.016))
        }
    }

    /// "Olhos piscando sempre": an irregular blink loop that runs the
    /// whole time the mascot is on screen, pausing while a bob/poke plays.
    private func startBlinking() {
        Task { @MainActor in
            while !Task.isCancelled {
                var rng = SystemRandomNumberGenerator()
                let interval = PuppetMotion.blinkInterval(rng: &rng)
                try? await Task.sleep(for: .seconds(interval))
                guard !isBusy, !reduceMotion else { continue }
                eyeState = .closed
                try? await Task.sleep(for: .milliseconds(130))
                eyeState = .open
            }
        }
    }

    private func play(bob variant: BobVariant) {
        let sequence = PuppetMotion.staged(
            PuppetMotion.bobSteps(variant),
            anticipation: useAnticipation,
            followThrough: useFollowThrough
        )
        steps = sequence
        animationStart = Date()
        isBusy = true
        scheduleFinish(after: sequence, scaledBy: durationScale)
    }

    private func play(poke variant: PokeVariant) {
        let sequence = PuppetMotion.staged(
            PuppetMotion.pokeSteps(variant),
            anticipation: useAnticipation,
            followThrough: useFollowThrough
        )
        eyeState = .annoyed
        steps = sequence
        animationStart = Date()
        isBusy = true
        scheduleFinish(after: sequence, scaledBy: durationScale) {
            self.eyeState = .open
        }
    }

    /// Releases the busy flag once the sequence's scaled duration passed —
    /// the pose itself returns to identity purely (see `pose`).
    private func scheduleFinish(
        after sequence: [MotionStep],
        scaledBy scale: Double = 1,
        onFinish: (() -> Void)? = nil
    ) {
        let total = sequence.reduce(0) { $0 + $1.duration } * scale
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(total))
            isBusy = false
            steps = []
            animationStart = nil
            onFinish?()
        }
    }
}
