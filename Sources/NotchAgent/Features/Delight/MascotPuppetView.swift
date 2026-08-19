import SwiftUI

/// One keyframe of a mascot animation — the puppet plays a small sequence
/// of these with springs. `.identity` is the settled pose.
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
}

/// The pixel-art face drawn OVER the sprite at the asset's real eye
/// positions: open dots, a closed line for blinks, slanted strokes when
/// annoyed. Pure decoration, never hit-testable.
public struct MascotFaceView: View {
    public let state: EyeState

    public init(state: EyeState) {
        self.state = state
    }

    public var body: some View {
        Canvas { context, size in
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
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The living mascot: rocks when the panel opens (varied), always reacts
/// to a poke with displeasure, and blinks constantly. Self-contained —
/// local state only, no engine dependency, so the animation can never be
/// silently skipped.
public struct MascotPuppetView<Content: View>: View {
    private let content: Content
    private let pokeCooldown: TimeInterval = 2

    @State private var transform: MotionStep = .identity
    @State private var eyeState: EyeState = .open
    @State private var isBusy = false
    @State private var lastPokeAt = Date.distantPast
    @State private var playTask: Task<Void, Never>?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .scaleEffect(y: transform.scaleY, anchor: .bottom)
            .rotationEffect(.degrees(transform.rotationDegrees))
            .offset(y: transform.offsetY)
            .overlay { MascotFaceView(state: eyeState) }
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

    /// "Olhos piscando sempre": an irregular blink loop that runs the
    /// whole time the mascot is on screen, pausing while a bob/poke plays.
    private func startBlinking() {
        Task { @MainActor in
            while !Task.isCancelled {
                var rng = SystemRandomNumberGenerator()
                let interval = PuppetMotion.blinkInterval(rng: &rng)
                try? await Task.sleep(for: .seconds(interval))
                guard !isBusy, !reduceMotion else { continue }
                withAnimation(.easeInOut(duration: 0.06)) { eyeState = .closed }
                try? await Task.sleep(for: .milliseconds(130))
                withAnimation(.easeInOut(duration: 0.08)) { eyeState = .open }
            }
        }
    }

    private func play(bob variant: BobVariant) {
        play(steps: PuppetMotion.bobSteps(variant))
    }

    private func play(poke variant: PokeVariant) {
        eyeState = .annoyed
        play(steps: PuppetMotion.pokeSteps(variant)) {
            withAnimation(.easeInOut(duration: 0.15)) { eyeState = .open }
        }
    }

    private func play(steps: [MotionStep], onFinish: (() -> Void)? = nil) {
        playTask?.cancel()
        isBusy = true
        playTask = Task { @MainActor in
            for step in steps {
                guard !Task.isCancelled else { break }
                withAnimation(.spring(duration: step.duration, bounce: 0.4)) {
                    transform = step
                }
                try? await Task.sleep(for: .seconds(step.duration + 0.05))
            }
            guard !Task.isCancelled else { return }
            isBusy = false
            onFinish?()
        }
    }
}
