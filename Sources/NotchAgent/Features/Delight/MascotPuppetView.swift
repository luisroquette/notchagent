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
    case swingUpDown, swayPendulum, wobbleFall, hopBob, bow, shiver, doubleTake, yawnStretch
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
        case .yawnStretch: [
            // Compound midnight yawn: stretch up, hold the stretch with a
            // drowsy lean (eyes go droopy via context, "z z z" floats up).
            MotionStep(scaleY: 1.06, rotationDegrees: -6, duration: 0.4),
            MotionStep(scaleY: 1.06, rotationDegrees: -6, duration: 0.5),
            MotionStep(duration: 0.5),
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

    /// The eyes are DERIVED, not stored: blink always wins, a startle
    /// opens wide before settling into annoyance, drowsy contexts wear
    /// heavy lids, excited contexts open wide.
    public static func derivedEyeState(
        context: MascotContext?,
        poke: PokeVariant?,
        elapsed: Double,
        blinking: Bool
    ) -> EyeState {
        if blinking { return .closed }
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
    private let pokeCooldown: TimeInterval = 2

    @State private var steps: [MotionStep] = []
    @State private var animationStart: Date?
    @State private var isBlinking = false
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(MascotMind.self) private var mind

    public init(spriteName: String, reactive: Bool = true) {
        self.spriteName = spriteName
        self.reactive = reactive
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
                // Aspect-preserving sprite rect, centered — the assets are
                // wide (367×255); drawing into the square slot stretches
                // them vertically.
                let spriteRect = Self.spriteRect(imageSize: spriteImage?.size, canvasSize: size)
                // Ground shadow first, under the sprite layer: it shrinks
                // and fades as the mascot lifts, and never follows the
                // pose's rotation — contact lives on the ground.
                let shadowScale = PuppetMotion.shadowScale(offsetY: pose.offsetY)
                let shadowRect = CGRect(
                    x: spriteRect.midX - spriteRect.width * 0.30 * shadowScale,
                    y: spriteRect.maxY - 1.5,
                    width: spriteRect.width * 0.60 * shadowScale,
                    height: max(1.5, spriteRect.height * 0.09 * shadowScale)
                )
                context.fill(
                    Path(ellipseIn: shadowRect),
                    with: .color(Color.black.opacity(PuppetMotion.shadowOpacity(offsetY: pose.offsetY)))
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
                    // scale, rotate, translate back, then the pose offset
                    // (canvas y is down, so a negative offsetY lifts).
                    layer.translateBy(x: spriteRect.midX, y: spriteRect.maxY)
                    layer.scaleBy(x: pow(squash, -0.5), y: pose.scaleY * squash * breathing)
                    layer.rotate(by: .degrees(pose.rotationDegrees + headTurn))
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
                    let eyes = PuppetMotion.derivedEyeState(
                        context: activeContext,
                        poke: activePoke,
                        elapsed: animationStart.map { timeline.date.timeIntervalSince($0) } ?? 0,
                        blinking: isBlinking
                    )
                    drawFace(state: eyes, context: layer, rect: spriteRect)
                }
                drawContextExtras(context: context, size: size, spriteRect: spriteRect, now: timeline.date)
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
            // Pokes are PERSONAL: local round-robin, this mascot only.
            var cursor = pokeCursor
            let variant = DelightCatalog.selectPoke(cursor: &cursor)
            pokeCursor = cursor
            activeContext = .poke
            activePoke = variant
            play(poke: variant)
        }
        .onContinuousHover { phase in
            // The head follows the cursor while it's over the mascot;
            // leaving the slot resets the gaze.
            switch phase {
            case .active(let location):
                cursorOffset = min(max((location.x - 32.0) / 32.0, -1), 1)
            case .ended:
                cursorOffset = 0
            }
        }
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
        case .wide:
            // Startled: the eyes blow up.
            let w = eyeWidth * 1.5
            let h = eyeHeight * 1.4
            for eye in [left, right] {
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: eye.x - w / 2, y: eye.y - h / 2,
                        width: w, height: h
                    )),
                    with: .color(color)
                )
            }
        case .droopy:
            // Heavy lids: half-height eyes with a lid band resting on top.
            let h = eyeHeight * 0.55
            for eye in [left, right] {
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: eye.x - eyeWidth / 2, y: eye.y - h / 2,
                        width: eyeWidth, height: h
                    )),
                    with: .color(color)
                )
                var lid = Path()
                lid.move(to: CGPoint(x: eye.x - eyeWidth * 0.6, y: eye.y - h * 0.6))
                lid.addLine(to: CGPoint(x: eye.x + eyeWidth * 0.6, y: eye.y - h * 0.6))
                context.stroke(lid, with: .color(color), lineWidth: max(1.5, rect.height * 0.016))
            }
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
                isBlinking = true
                try? await Task.sleep(for: .milliseconds(130))
                isBlinking = false
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
        scheduleFinish(after: sequence, scaledBy: durationScale) {
            self.activeContext = nil
            self.activePoke = nil
        }
    }

    private func play(poke variant: PokeVariant) {
        let sequence = PuppetMotion.staged(
            PuppetMotion.pokeSteps(variant),
            anticipation: useAnticipation,
            followThrough: useFollowThrough
        )
        steps = sequence
        animationStart = Date()
        isBusy = true
        scheduleFinish(after: sequence, scaledBy: durationScale) {
            self.activePoke = nil
            self.activeContext = nil
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
