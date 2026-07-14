import SwiftUI

/// The positive counterpart to AlertMomentView: a brief, calm takeover
/// celebrating a provider going from blocked back to usable mid-work.
struct RestoreMomentView: View {
    let moment: RestoreMoment
    let onDismiss: () -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = (sin(t * 1.4 * .pi) + 1) / 2

            HStack(spacing: 20) {
                PixelGlyph(tint: Theme.ok, distress: 0)
                    .frame(width: 96, height: 74)

                VStack(alignment: .leading, spacing: 7) {
                    GaugeLabel(
                        text: "\(moment.provider.shortName) · \(moment.isWeekly ? "WEEKLY" : "5H") WINDOW",
                        color: Theme.textSecondary,
                        size: 9
                    )
                    Text("\(Int(moment.remaining.rounded()))%")
                        .font(Theme.numeral(46))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ok)
                    HStack(spacing: 6) {
                        GaugeLabel(text: "BACK ONLINE", color: Theme.ok, size: 10)
                        Text("session restored — back to work")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    SegmentedMeter(percent: moment.remaining, segments: 16, tint: Theme.ok, height: 9)
                }
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.ok.opacity(0.05 + 0.05 * pulse))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.ok.opacity(0.25 + 0.3 * pulse), lineWidth: 2)
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
