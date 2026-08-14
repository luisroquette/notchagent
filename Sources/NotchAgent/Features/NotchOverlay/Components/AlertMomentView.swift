import SwiftUI

/// Full-panel takeover when a "space left" threshold fires. Severity escalates
/// from a gentle amber pulse at 25% to an alarm-red tremor at 5% — the closer
/// to empty, the louder the moment. 25/15/10 auto-dismiss; 5% waits for a click.
struct AlertMomentView: View {
    let alert: ThresholdAlert
    let onDismiss: () -> Void

    private var severityColor: Color {
        switch alert.threshold {
        case ...5: Theme.danger
        case ...25: Theme.warning
        case ...50: Theme.caution
        default: Theme.coral
        }
    }

    /// Pulse frequency ramps with severity.
    private var pulseSpeed: Double {
        switch alert.threshold {
        case 5: 5.0
        case ...25: 3.0
        case ...50: 1.8
        default: 1.1
        }
    }

    private var headline: String {
        switch alert.threshold {
        case 5: "ALMOST EMPTY"
        case ...25: "RUNNING LOW"
        case ...50: "HALFWAY"
        case ...75: "ON TRACK"
        default: "FULL TANK"
        }
    }

    private var message: String {
        let window = alert.isWeekly ? "weekly limit" : "5h session"
        switch alert.threshold {
        case 5: return "Your \(window) is about to run out."
        case ...25: return "Plan the next prompts — \(window) is running low."
        case ...50: return "Half of the \(window) remains."
        case ...75: return "A quarter of the \(window) has been used."
        default: return "A new \(window) is ready."
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = (sin(t * pulseSpeed * .pi) + 1) / 2
            let tremor = alert.threshold == 5 ? sin(t * 34) * 1.6 : 0

            HStack(spacing: 20) {
                PixelGlyph(tint: severityColor, distress: 1 - alert.remaining / 100)
                    .frame(width: 96, height: 74)
                    .offset(x: tremor)

                VStack(alignment: .leading, spacing: 7) {
                    GaugeLabel(
                        text: "\(alert.provider.shortName) · \(alert.isWeekly ? "WEEKLY" : "5H") WINDOW",
                        color: Theme.textSecondary,
                        size: 9
                    )
                    Text("\(Int(alert.remaining.rounded()))%")
                        .font(Theme.numeral(46))
                        .monospacedDigit()
                        .foregroundStyle(severityColor)
                    HStack(spacing: 6) {
                        GaugeLabel(text: headline, color: severityColor, size: 10)
                        Text(message)
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    SegmentedMeter(percent: alert.remaining, segments: 16, tint: severityColor, height: 9)
                }
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(severityColor.opacity(0.06 + 0.08 * pulse))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        severityColor.opacity(0.30 + 0.65 * pulse),
                        lineWidth: alert.threshold <= 25 ? 3 : 2
                    )
            )
            .overlay(alignment: .bottomTrailing) {
                GaugeLabel(
                    text: alert.threshold == 5 ? "CLICK TO DISMISS" : "CLICK OR WAIT",
                    color: Theme.textFaint,
                    size: 7.5
                )
                .padding(10)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        // Auto-dismiss is owned by UsageStore so it survives the view being
        // collapsed away mid-countdown (ghost-alert review finding).
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}
