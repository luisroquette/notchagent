import SwiftUI

/// 5h-window burn chart. Fuel story at a glance: filled coral area = quota
/// burned, dotted line = projection, red band = danger zone. Hovering scrubs
/// the timeline with a crosshair + value bubble, instrument-style.
struct BurnChartView: View {
    let samples: [PercentSample]
    let projection: BurnRate.Projection?
    let windowStart: Date
    let windowEnd: Date

    @State private var hoverX: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                GaugeLabel(text: "START \(Format.time(windowStart))", color: Theme.textFaint, size: 8)
                Spacer()
                GaugeLabel(text: "RESET \(Format.time(windowEnd))", color: Theme.coralDim, size: 8)
            }
        }
    }

    // MARK: Geometry helpers

    private var span: TimeInterval { max(windowEnd.timeIntervalSince(windowStart), 60) }

    private var visibleSamples: [PercentSample] {
        samples
            .filter { $0.date >= windowStart && $0.date <= windowEnd }
            .sorted { $0.date < $1.date }
    }

    /// History polyline plus the projected end point (flagged), for scrubbing.
    private var polyline: [(date: Date, percent: Double, projected: Bool)] {
        var points = visibleSamples.map { ($0.date, $0.percent, false) }
        guard let last = visibleSamples.last, let projection, projection.percentPerHour > 0.1 else {
            return points
        }
        if let exhaustsAt = projection.exhaustsAt, exhaustsAt <= windowEnd {
            points.append((exhaustsAt, 100, true))
        } else {
            let hours = windowEnd.timeIntervalSince(last.date) / 3600
            points.append((windowEnd, min(100, last.percent + projection.percentPerHour * hours), true))
        }
        return points
    }

    private func interpolate(at date: Date) -> (percent: Double, projected: Bool)? {
        let points = polyline
        guard let first = points.first else { return nil }
        if date <= first.date { return (first.percent, first.projected) }
        for (a, b) in zip(points, points.dropFirst()) where date <= b.date {
            let fraction = date.timeIntervalSince(a.date) / max(b.date.timeIntervalSince(a.date), 1)
            return (a.percent + (b.percent - a.percent) * fraction, b.projected)
        }
        return points.last.map { ($0.percent, $0.projected) }
    }

    // MARK: Drawing

    private func chart(in size: CGSize) -> some View {
        func x(_ date: Date) -> CGFloat {
            CGFloat(date.timeIntervalSince(windowStart) / span) * size.width
        }
        func y(_ percent: Double) -> CGFloat {
            size.height - CGFloat(min(max(percent, 0), 100) / 100) * size.height
        }

        return Canvas { context, canvasSize in
            drawFrame(context: context, size: canvasSize, y: y)
            drawHourTicks(context: context, size: canvasSize, x: x)

            let visible = visibleSamples
            guard let first = visible.first, let last = visible.last else {
                context.draw(
                    Text("watching your burn — the chart fills in as the session runs")
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textDim),
                    at: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                )
                return
            }

            // Burned area under the history line.
            var area = Path()
            area.move(to: CGPoint(x: x(first.date), y: canvasSize.height))
            for sample in visible {
                area.addLine(to: CGPoint(x: x(sample.date), y: y(sample.percent)))
            }
            area.addLine(to: CGPoint(x: x(last.date), y: canvasSize.height))
            area.closeSubpath()
            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [Theme.coral.opacity(0.35), Theme.coral.opacity(0.03)]),
                    startPoint: CGPoint(x: 0, y: y(100)),
                    endPoint: CGPoint(x: 0, y: canvasSize.height)
                )
            )

            // History line.
            var history = Path()
            history.move(to: CGPoint(x: x(first.date), y: y(first.percent)))
            for sample in visible.dropFirst() {
                history.addLine(to: CGPoint(x: x(sample.date), y: y(sample.percent)))
            }
            context.stroke(
                history,
                with: .color(Theme.coral),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            // Projection + projected-empty marker.
            if let target = polyline.last, target.projected {
                var projected = Path()
                projected.move(to: CGPoint(x: x(last.date), y: y(last.percent)))
                projected.addLine(to: CGPoint(x: x(target.date), y: y(target.percent)))
                let runsOut = target.percent >= 100 && target.date < windowEnd
                context.stroke(
                    projected,
                    with: .color(runsOut ? Theme.danger.opacity(0.8) : Theme.coralDim),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [3, 4])
                )
                if runsOut {
                    let marker = CGPoint(x: x(target.date), y: y(100))
                    context.fill(
                        Path(ellipseIn: CGRect(x: marker.x - 4, y: marker.y - 4, width: 8, height: 8)),
                        with: .color(Theme.danger)
                    )
                    context.draw(
                        Text("EMPTY \(Format.time(target.date))")
                            .font(Theme.label(7.5))
                            .foregroundStyle(Theme.danger),
                        at: CGPoint(x: min(marker.x, canvasSize.width - 48), y: marker.y + 12)
                    )
                }
            }

            // "Now": vertical hairline + white dot, label above the dot.
            let nowPoint = CGPoint(x: x(last.date), y: y(last.percent))
            var nowLine = Path()
            nowLine.move(to: CGPoint(x: nowPoint.x, y: 0))
            nowLine.addLine(to: CGPoint(x: nowPoint.x, y: canvasSize.height))
            context.stroke(nowLine, with: .color(Theme.gridline), lineWidth: 1)
            context.fill(
                Path(ellipseIn: CGRect(x: nowPoint.x - 3.5, y: nowPoint.y - 3.5, width: 7, height: 7)),
                with: .color(Theme.marker)
            )
            context.draw(
                Text("NOW").font(Theme.label(7)).foregroundStyle(Theme.textDim),
                at: CGPoint(
                    x: min(max(nowPoint.x, 16), canvasSize.width - 16),
                    y: max(nowPoint.y - 13, 8)
                )
            )

            drawScrubber(context: context, size: canvasSize, x: x, y: y)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private func drawFrame(context: GraphicsContext, size: CGSize, y: (Double) -> CGFloat) {
        // Danger zone above 90% used.
        context.fill(
            Path(CGRect(x: 0, y: 0, width: size.width, height: y(90))),
            with: .color(Theme.danger.opacity(0.05))
        )
        var dangerLine = Path()
        dangerLine.move(to: CGPoint(x: 0, y: y(90)))
        dangerLine.addLine(to: CGPoint(x: size.width, y: y(90)))
        context.stroke(
            dangerLine,
            with: .color(Theme.danger.opacity(0.30)),
            style: StrokeStyle(lineWidth: 1, dash: [2, 3])
        )

        for level in [25.0, 50.0, 75.0] {
            var grid = Path()
            grid.move(to: CGPoint(x: 22, y: y(level)))
            grid.addLine(to: CGPoint(x: size.width, y: y(level)))
            context.stroke(grid, with: .color(Theme.gridline), lineWidth: 1)
            context.draw(
                Text("\(Int(level))").font(Theme.label(7)).foregroundStyle(Theme.textFaint),
                at: CGPoint(x: 10, y: y(level))
            )
        }
        context.draw(
            Text("% USED").font(Theme.label(6.5)).foregroundStyle(Theme.textFaint),
            at: CGPoint(x: 26, y: y(90) + 10),
            anchor: .leading
        )
    }

    private func drawHourTicks(context: GraphicsContext, size: CGSize, x: (Date) -> CGFloat) {
        var calendar = Calendar.current
        calendar.timeZone = .current
        guard var tick = calendar.nextDate(
            after: windowStart, matching: DateComponents(minute: 0), matchingPolicy: .nextTime
        ) else { return }

        while tick < windowEnd {
            let tickX = x(tick)
            if tickX > 26, tickX < size.width - 26 {
                var mark = Path()
                mark.move(to: CGPoint(x: tickX, y: size.height - 5))
                mark.addLine(to: CGPoint(x: tickX, y: size.height))
                context.stroke(mark, with: .color(Theme.gridStrong), lineWidth: 1)
                context.draw(
                    Text("\(calendar.component(.hour, from: tick))h")
                        .font(Theme.label(6.5))
                        .foregroundStyle(Theme.textFaint),
                    at: CGPoint(x: tickX, y: size.height - 11)
                )
            }
            tick = tick.addingTimeInterval(3600)
        }
    }

    /// Crosshair + value bubble following the pointer.
    private func drawScrubber(
        context: GraphicsContext, size: CGSize,
        x: (Date) -> CGFloat, y: (Double) -> CGFloat
    ) {
        guard let hoverX, hoverX >= 0, hoverX <= size.width, !polyline.isEmpty else { return }
        let date = windowStart.addingTimeInterval(span * Double(hoverX / size.width))
        guard let value = interpolate(at: date) else { return }

        var crosshair = Path()
        crosshair.move(to: CGPoint(x: hoverX, y: 0))
        crosshair.addLine(to: CGPoint(x: hoverX, y: size.height))
        context.stroke(crosshair, with: .color(Theme.gridStrong), lineWidth: 1)

        let dotY = y(value.percent)
        context.stroke(
            Path(ellipseIn: CGRect(x: hoverX - 4, y: dotY - 4, width: 8, height: 8)),
            with: .color(value.projected ? Theme.coralDim : Theme.marker),
            lineWidth: 1.5
        )

        let label = Text("\(Format.time(date)) · \(Int(value.percent.rounded()))% used\(value.projected ? " · proj" : "")")
            .font(Theme.label(8))
            .foregroundStyle(Theme.textPrimary)
        let resolved = context.resolve(label)
        let textSize = resolved.measure(in: CGSize(width: 240, height: 20))
        let bubbleWidth = textSize.width + 14
        let bubbleX = min(max(hoverX - bubbleWidth / 2, 4), size.width - bubbleWidth - 4)
        let bubble = CGRect(x: bubbleX, y: 6, width: bubbleWidth, height: textSize.height + 8)
        context.fill(
            Path(roundedRect: bubble, cornerRadius: 5),
            with: .color(Theme.bubble)
        )
        context.stroke(
            Path(roundedRect: bubble, cornerRadius: 5),
            with: .color(Theme.hairline),
            lineWidth: 0.5
        )
        context.draw(resolved, at: CGPoint(x: bubble.midX, y: bubble.midY), anchor: .center)
    }
}
