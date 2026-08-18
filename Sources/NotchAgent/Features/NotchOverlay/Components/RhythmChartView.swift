import SwiftUI

/// 24-bar hourly rhythm: coral bars scaled by activity, current hour in white —
/// the stick's Ritmo por hora, rendered natively. Hovering a bar outlines it
/// and shows the exact hour + token count, following the pointer across
/// hours the same way BurnChartView's scrubber follows it across lines.
struct RhythmChartView: View {
    /// tokens per hour-of-day (index 0–23).
    let totals: [Int]

    @State private var hoverX: CGFloat?

    /// Below this, the current hour has barely started — extrapolating its
    /// so-far total to a full hour would swing wildly (2 minutes in, a
    /// single request can look like an all-day binge). Withholding the
    /// projection until there's enough signal is the honest choice, not a
    /// tuning knob: a Karpathy simplicity call, not a design one.
    private static let currentHourGraceFraction: Double = 0.15

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                chart(in: proxy.size)
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let point): hoverX = point.x
                        case .ended: hoverX = nil
                        }
                    }
            }
            HStack {
                ForEach([0, 6, 12, 18, 23], id: \.self) { hour in
                    GaugeLabel(text: "\(hour)h", color: Theme.textFaint, size: 8)
                    if hour != 23 { Spacer() }
                }
            }
        }
    }

    private func chart(in size: CGSize) -> some View {
        let maxValue = max(totals.max() ?? 1, 1)
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        // How far into currentHour "now" is — the current bar's real height
        // only reflects tokens burned so far, not the finished hour every
        // other bar shows, so it needs to look unfinished, not just smaller.
        let currentHourElapsedFraction = Double(calendar.component(.minute, from: now)) / 60.0
        let slot = size.width / 24
        let gap = slot * 0.28
        let barWidth = max(1, slot - gap)
        let hoveredHour = hoverX.map { min(23, max(0, Int($0 / slot))) }

        return Canvas { context, canvasSize in
            for hour in 0..<24 {
                let ratio = Double(totals[hour]) / Double(maxValue)
                let barHeight = max(3, canvasSize.height * ratio)
                let rect = CGRect(
                    x: CGFloat(hour) * slot + gap / 2,
                    y: canvasSize.height - barHeight,
                    width: barWidth, height: barHeight
                )
                let path = Path(roundedRect: rect, cornerRadius: 2, style: .continuous)
                context.fill(path, with: .color(barColor(hour: hour, currentHour: currentHour, ratio: ratio)))
                if hoveredHour == hour {
                    context.stroke(path, with: .color(Theme.textPrimary), lineWidth: 1)
                }
                if hour == currentHour, ratio > 0, currentHourElapsedFraction >= Self.currentHourGraceFraction {
                    drawInProgressCap(
                        context: context, barRect: rect, ratio: ratio,
                        elapsedFraction: currentHourElapsedFraction, canvasHeight: canvasSize.height
                    )
                }
            }
            if let hoveredHour {
                drawTooltip(
                    context: context, size: canvasSize, hour: hoveredHour,
                    currentHour: currentHour, currentHourElapsedFraction: currentHourElapsedFraction,
                    slot: slot, maxValue: maxValue
                )
            }
        }
    }

    /// Same visual grammar as BurnChartView's projection (dashed = not real
    /// yet), reused here for the same reason it exists there: the current
    /// hour's bar is real up to "now" and a naive linear extrapolation
    /// above that — showing that boundary honestly beats a bar that reads
    /// as a settled total when the hour hasn't happened yet.
    private func drawInProgressCap(
        context: GraphicsContext, barRect: CGRect, ratio: Double, elapsedFraction: Double, canvasHeight: CGFloat
    ) {
        let projectedRatio = min(1, ratio / elapsedFraction)
        let projectedHeight = canvasHeight * projectedRatio
        guard projectedHeight > barRect.height + 1 else { return }
        let cap = CGRect(
            x: barRect.minX, y: canvasHeight - projectedHeight,
            width: barRect.width, height: projectedHeight - barRect.height
        )
        context.stroke(
            Path(roundedRect: cap, cornerRadius: 2, style: .continuous),
            with: .color(Theme.coralDim),
            style: StrokeStyle(lineWidth: 1, dash: [2, 3])
        )
    }

    private func barColor(hour: Int, currentHour: Int, ratio: Double) -> Color {
        if hour == currentHour {
            return Theme.marker
        }
        if ratio <= 0 {
            return Theme.socket
        }
        // Busier hours glow hotter, like the stick's heat-scaled bars.
        return Theme.coral.opacity(0.35 + ratio * 0.65)
    }

    /// Crosshair + value bubble for the hovered bar, clamped on-canvas the
    /// same way BurnChartView's bubble is — mirrors that file's scrubber so
    /// both pages read as one consistent instrument, not two different UIs.
    private func drawTooltip(
        context: GraphicsContext, size: CGSize, hour: Int, currentHour: Int,
        currentHourElapsedFraction: Double, slot: CGFloat, maxValue: Int
    ) {
        let ratio = Double(totals[hour]) / Double(maxValue)
        let barTopY = size.height - max(3, size.height * ratio)
        let centerX = (CGFloat(hour) + 0.5) * slot
        let inProgress = hour == currentHour && currentHourElapsedFraction < 1

        var crosshair = Path()
        crosshair.move(to: CGPoint(x: centerX, y: 0))
        crosshair.addLine(to: CGPoint(x: centerX, y: size.height))
        context.stroke(crosshair, with: .color(Theme.gridStrong), lineWidth: 1)

        let label = Text(
            "\(hour)h\(hour == currentHour ? " · NOW" : "") · " +
            "\(Format.tokens(totals[hour])) tokens\(inProgress ? " so far" : "")"
        )
            .font(Theme.label(8))
            .foregroundStyle(Theme.textPrimary)
        let resolved = context.resolve(label)
        let textSize = resolved.measure(in: CGSize(width: 200, height: 20))
        let bubbleWidth = textSize.width + 14
        let bubbleHeight = textSize.height + 8
        let bubbleX = min(max(centerX - bubbleWidth / 2, 4), size.width - bubbleWidth - 4)
        let bubbleY = max(barTopY - bubbleHeight - 8, 4)

        let bubble = CGRect(x: bubbleX, y: bubbleY, width: bubbleWidth, height: bubbleHeight)
        context.fill(Path(roundedRect: bubble, cornerRadius: 5), with: .color(Theme.bubble))
        context.stroke(Path(roundedRect: bubble, cornerRadius: 5), with: .color(Theme.hairline), lineWidth: 0.5)
        context.draw(resolved, at: CGPoint(x: bubble.midX, y: bubble.midY), anchor: .center)
    }
}

/// Clickable carousel dots; the active page is a coral pill.
struct PagerDots: View {
    @Binding var page: Int
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    page = index
                } label: {
                    Capsule()
                        .fill(index == page ? Theme.coral : Theme.socket)
                        .frame(width: index == page ? 18 : 7, height: 7)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(duration: 0.3), value: page)
    }
}
