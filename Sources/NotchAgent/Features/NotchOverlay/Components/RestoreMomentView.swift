import SwiftUI

/// The positive counterpart to AlertMomentView: the tank refilling on screen.
/// Animates from `previousRemaining` (how low it got) up to `remaining` (where
/// it landed) over ~1.8s — the color sweeps the same ramp the rest of the app
/// uses (red → orange → yellow → green) and the mascot's ears come back up as
/// the fill climbs, landing happy once it settles.
struct RestoreMomentView: View {
    let moment: RestoreMoment
    let onDismiss: () -> Void

    private let fillDuration: Double = 1.8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(moment.firedAt))
            let progress = min(elapsed / fillDuration, 1)
            let eased = 1 - pow(1 - progress, 3) // ease-out cubic
            let displayed = moment.previousRemaining + (moment.remaining - moment.previousRemaining) * eased
            let color = Theme.ramp(100 - displayed)
            let distress = max(0, min(1, 1 - displayed / 100))
            let pulse = (sin(context.date.timeIntervalSinceReferenceDate * 1.4 * .pi) + 1) / 2

            // A small settling "boing" once the fill completes.
            let settledT = max(0, elapsed - fillDuration)
            let bounce = progress >= 1 ? sin(settledT * 6) * exp(-settledT * 3) * 0.06 : 0

            HStack(spacing: 20) {
                PixelGlyph(tint: color, distress: distress)
                    .frame(width: 96, height: 74)
                    .scaleEffect(1 + bounce)

                VStack(alignment: .leading, spacing: 7) {
                    GaugeLabel(
                        text: "\(moment.provider.shortName) · \(moment.isWeekly ? "WEEKLY" : "5H") WINDOW",
                        color: Theme.textSecondary,
                        size: 9
                    )
                    Text("\(Int(displayed.rounded()))%")
                        .font(Theme.numeral(46))
                        .monospacedDigit()
                        .foregroundStyle(color)
                    HStack(spacing: 6) {
                        GaugeLabel(text: progress >= 1 ? "BACK ONLINE" : "REFILLING", color: color, size: 10)
                        Text(progress >= 1 ? "session restored — back to work" : "topping back up…")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    SegmentedMeter(percent: displayed, segments: 16, tint: color, height: 9)
                }
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(color.opacity(0.05 + 0.05 * pulse))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(color.opacity(0.25 + 0.3 * pulse), lineWidth: 2)
            )
            .overlay(alignment: .bottomTrailing) {
                GaugeLabel(text: "CLICK TO DISMISS", color: Theme.textFaint, size: 7.5)
                    .padding(10)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}
