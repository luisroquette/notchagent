import SwiftUI

/// The motion table: every gesture is a small transform over the existing
/// sprite — no new art, no timeline. Reduce Motion maps everything to
/// `.none` at the call site.
public enum PuppetMotion {
    public struct Parameters: Equatable {
        public var scaleY: Double
        public var rotationDegrees: Double
        public var offsetY: Double
        public var duration: Double

        public init(scaleY: Double, rotationDegrees: Double, offsetY: Double, duration: Double) {
            self.scaleY = scaleY
            self.rotationDegrees = rotationDegrees
            self.offsetY = offsetY
            self.duration = duration
        }
    }

    /// Amplitudes tuned to be SEEN on a 48pt sprite from across the screen:
    /// under ~4pt of offset or ~5° of rotation the motion is invisible —
    /// delight nobody notices is just a frame wasted.
    public static func parameters(for gesture: MascotGesture) -> Parameters {
        switch gesture {
        case .blink: Parameters(scaleY: 0.78, rotationDegrees: 0, offsetY: 0, duration: 0.18)
        case .tilt: Parameters(scaleY: 1, rotationDegrees: 10, offsetY: 0, duration: 0.35)
        case .hop: Parameters(scaleY: 1, rotationDegrees: 0, offsetY: -12, duration: 0.4)
        case .stretch: Parameters(scaleY: 1.10, rotationDegrees: 0, offsetY: 0, duration: 0.3)
        case .nod: Parameters(scaleY: 0.96, rotationDegrees: 0, offsetY: 6, duration: 0.35)
        case .yawn: Parameters(scaleY: 1.05, rotationDegrees: -6, offsetY: 0, duration: 0.5)
        case .lookAtCursor: Parameters(scaleY: 1, rotationDegrees: 5, offsetY: 0, duration: 0.3)
        case .none, .ignored: Parameters(scaleY: 1, rotationDegrees: 0, offsetY: 0, duration: 0)
        }
    }
}

/// Wraps the mascot sprite and performs the active gesture as a spring
/// transform. The yawn adds a drifting "z z z". Pure decoration.
public struct MascotPuppetView<Content: View>: View {
    public let gesture: MascotGesture
    public let enabled: Bool
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(gesture: MascotGesture, enabled: Bool, @ViewBuilder content: () -> Content) {
        self.gesture = gesture
        self.enabled = enabled
        self.content = content()
    }

    public var body: some View {
        let motion = PuppetMotion.parameters(for: (reduceMotion || !enabled) ? .none : gesture)
        content
            .scaleEffect(y: motion.scaleY, anchor: .bottom)
            .rotationEffect(.degrees(motion.rotationDegrees))
            .offset(y: motion.offsetY)
            .animation(.spring(duration: motion.duration, bounce: 0.35), value: gesture)
            .overlay(alignment: .topTrailing) {
                if gesture == .yawn, !reduceMotion, enabled {
                    Text("z z z")
                        .font(Theme.body(8, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                        .offset(y: -8)
                        .transition(.opacity)
                }
            }
    }
}
