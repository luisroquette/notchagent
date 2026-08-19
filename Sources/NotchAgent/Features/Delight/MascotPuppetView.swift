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
public enum BobVariant: String, CaseIterable {
    case swingUpDown, swayPendulum, wobbleFall, hopBob
}

/// Touch reactions: poking the mascot ALWAYS gets an annoyed response.
public enum PokeVariant: String, CaseIterable {
    case startleJump, annoyedWiggle, shrinkSulk
}

public enum EyeState: Equatable {
    case open, closed, annoyed
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
    /// interpolation with smoothstep easing. nil start = identity. After the
    /// last step the pose holds identity (the sequence settled).
    public static func pose(steps: [MotionStep], start: Date?, now: Date) -> MotionStep {
        guard let start, !steps.isEmpty else { return .identity }
        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= 0 else { return steps[0] }
        var accumulated: Double = 0
        var previous = MotionStep.identity
        for step in steps {
            let stepEnd = accumulated + step.duration
            if elapsed < stepEnd {
                let f = step.duration > 0
                    ? max(0, min(1, (elapsed - accumulated) / step.duration))
                    : 1
                let eased = f * f * (3 - 2 * f)
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                : PuppetMotion.pose(steps: steps, start: animationStart, now: timeline.date)
            Canvas { context, size in
                context.drawLayer { layer in
                    // Anchor at bottom-center: translate, scale, rotate,
                    // translate back, then the pose offset (canvas y is
                    // down, so a negative offsetY lifts the sprite).
                    layer.translateBy(x: size.width / 2, y: size.height)
                    layer.scaleBy(x: pose.scaleY, y: pose.scaleY)
                    layer.rotate(by: .degrees(pose.rotationDegrees))
                    layer.translateBy(x: -size.width / 2, y: -size.height)
                    layer.translateBy(x: 0, y: pose.offsetY)

                    if let image = spriteImage {
                        layer.draw(
                            Image(nsImage: image).resizable().interpolation(.none),
                            in: CGRect(origin: .zero, size: size)
                        )
                    } else {
                        layer.fill(
                            Path(CGRect(origin: .zero, size: size)),
                            with: .color(Theme.coral.opacity(0.4))
                        )
                    }
                    drawFace(state: eyeState, context: layer, size: size)
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            startBlinking()
            play(bob: BobVariant.allCases.randomElement()!)
        }
        .onHover { hovering in
            guard hovering, !reduceMotion else { return }
            let now = Date()
            guard now.timeIntervalSince(lastPokeAt) >= pokeCooldown else { return }
            lastPokeAt = now
            play(poke: PokeVariant.allCases.randomElement()!)
        }
    }

    /// The pixel-art face at the asset's real eye positions — drawn inside
    /// the sprite's layer so it follows every pose.
    private func drawFace(state: EyeState, context: GraphicsContext, size: CGSize) {
        let eyeWidth = max(2, size.width * 0.07)
        let eyeHeight = eyeWidth * 1.1
        let color = Color.black.opacity(0.88)

        func point(_ rel: CGPoint) -> CGPoint {
            CGPoint(x: rel.x * size.width, y: rel.y * size.height)
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
            let lineHeight = max(2, size.height * 0.02)
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
            context.stroke(strokes, with: .color(color), lineWidth: max(1.5, size.height * 0.016))
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
        let sequence = PuppetMotion.bobSteps(variant)
        steps = sequence
        animationStart = Date()
        isBusy = true
        scheduleFinish(after: sequence)
    }

    private func play(poke variant: PokeVariant) {
        let sequence = PuppetMotion.pokeSteps(variant)
        eyeState = .annoyed
        steps = sequence
        animationStart = Date()
        isBusy = true
        scheduleFinish(after: sequence) {
            self.eyeState = .open
        }
    }

    /// Releases the busy flag once the sequence's total duration passed —
    /// the pose itself returns to identity purely (see `pose`).
    private func scheduleFinish(after sequence: [MotionStep], onFinish: (() -> Void)? = nil) {
        let total = sequence.reduce(0) { $0 + $1.duration }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(total))
            isBusy = false
            steps = []
            animationStart = nil
            onFinish?()
        }
    }
}
