import SwiftUI

/// 5h-window burn chart. Fuel story at a glance: filled coral area = quota
/// burned, dotted line = projection, red band = danger zone. Hovering scrubs
/// the timeline with a crosshair + value bubble, instrument-style.
struct BurnChartView: View {
    let samples: [PercentSample]
    let projection: BurnRate.Projection?
    let windowStart: Date
    let windowEnd: Date
    /// Display name of the model the solid/dashed history line already
    /// represents (e.g. "Sonnet") — nil leaves the "NOW" label as plain
    /// "NOW" with no model name appended.
    let dominantModelShortName: String?
    /// The 3 (or fewer) other Claude tiers, each with a price ratio
    /// against the dominant model. Empty hides the alternate lines.
    let alternates: [ModelProjection.Alternate]

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

    /// Clamps `y` into `bounds`, then nudges it straight down in
    /// `minGap`-sized steps until it's at least `minGap` away from every
    /// value in `placed` — used to keep two alternate-line end labels from
    /// overlapping when their price ratios land them close together
    /// vertically, and to keep every label on-canvas (a line reaching 100%
    /// or 0% would otherwise draw its label off the top/bottom edge). The
    /// nudge loop stops once nudging further would exceed the upper bound,
    /// accepting a same-position overlap in the rare case of too many
    /// converging labels rather than looping forever or drawing past the
    /// bound. Pure and deterministic so it's unit-tested directly, unlike
    /// the rest of this file's Canvas drawing.
    nonisolated static func nonCollidingLabelY(
        _ y: CGFloat, avoiding placed: [CGFloat], minGap: CGFloat, clampedTo bounds: ClosedRange<CGFloat>
    ) -> CGFloat {
        var candidate = min(max(y, bounds.lowerBound), bounds.upperBound)
        while placed.contains(where: { abs($0 - candidate) < minGap }), candidate + minGap <= bounds.upperBound {
            candidate += minGap
        }
        return candidate
    }

    private var visibleSamples: [PercentSample] {
        samples
            .filter { $0.date >= windowStart && $0.date <= windowEnd }
            .sorted { $0.date < $1.date }
    }

    /// History polyline plus the projected end point (flagged), for scrubbing.
    /// Takes `visible` as a parameter (rather than re-deriving it from
    /// `visibleSamples`) so a single `chart(in:)` redraw computes it once
    /// and threads it through, instead of every caller re-filtering the
    /// full sample array — see the perf note at the `chart(in:)` call site.
    private func polyline(from visible: [PercentSample]) -> [(date: Date, percent: Double, projected: Bool)] {
        var points = visible.map { ($0.date, $0.percent, false) }
        guard let last = visible.last, let projection, projection.percentPerHour > 0.1 else {
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

    /// Same shape as `polyline`, scaled by `alternate.priceRatio` — "if
    /// these tokens had all been on this model instead." Stops drawing
    /// once it would cross 100% (that model would already be exhausted;
    /// no marker, this is a context line, not the primary instrument).
    private func alternatePolyline(
        _ alternate: ModelProjection.Alternate, visibleSamples visible: [PercentSample]
    ) -> [(date: Date, percent: Double)] {
        guard let last = visible.last else { return [] }

        var points: [(Date, Double)] = []
        for sample in visible {
            let scaled = min(100, sample.percent * alternate.priceRatio)
            points.append((sample.date, scaled))
            if scaled >= 100 { return points }
        }

        guard let projection, projection.percentPerHour > 0.1 else { return points }
        let scaledRate = projection.percentPerHour * alternate.priceRatio
        guard scaledRate > 0.1 else { return points }

        let lastPercent = points.last?.1 ?? 0
        let hoursToFull = (100 - lastPercent) / scaledRate
        let exhaustsAt = last.date.addingTimeInterval(hoursToFull * 3600)
        if exhaustsAt <= windowEnd {
            points.append((exhaustsAt, 100))
        } else {
            let hours = windowEnd.timeIntervalSince(last.date) / 3600
            points.append((windowEnd, min(100, lastPercent + scaledRate * hours)))
        }
        return points
    }

    private func interpolate(
        at date: Date, in points: [(date: Date, percent: Double, projected: Bool)]
    ) -> (percent: Double, projected: Bool)? {
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

            // `visible` and `points` are computed exactly once per redraw
            // and threaded into every consumer below (history line,
            // projection target, alternates, scrubber interpolation)
            // instead of each independently re-deriving them from
            // `visibleSamples`/`polyline` — during active hover
            // (`onContinuousHover`, up to 60-120/sec) that used to mean up
            // to 7 redundant evaluations per Canvas redraw.
            let points = polyline(from: visible)

            // Computed here (not just at its draw site further down) so
            // the label collision-avoidance seeding below has NOW's
            // y-position available before the alternates loop runs — the
            // hairline/dot/label are still drawn later, in their original
            // visual order (on top of the alternates).
            let nowPoint = CGPoint(x: x(last.date), y: y(last.percent))
            // The NOW label draws 13px above its dot (see the NOW-label
            // draw site below, which reuses this exact value) — seeding
            // collision-avoidance with `nowPoint.y` instead of this would
            // put the seed 13px off from where the label actually renders,
            // just outside the 12px minGap, so it would never actually
            // prevent an alternate's label from landing on top of it.
            let nowLabelY = max(nowPoint.y - 13, 8)

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

            // Projection + projected-empty marker. `emptyMarkerLabelY` and
            // `labelPositions` feed the collision-avoidance seeding
            // (Finding 3) and the scrubber-bubble collision check
            // (Finding 4) below.
            var emptyMarkerLabelY: CGFloat?
            var labelPositions: [CGPoint] = []
            if let target = points.last, target.projected {
                var projected = Path()
                projected.move(to: CGPoint(x: x(last.date), y: y(last.percent)))
                projected.addLine(to: CGPoint(x: x(target.date), y: y(target.percent)))
                let runsOut = target.percent >= 100 && target.date < windowEnd
                if runsOut {
                    // Actually running out: unchanged from before this fix round.
                    context.stroke(
                        projected,
                        with: .color(Theme.danger.opacity(0.8)),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [3, 4])
                    )
                    let marker = CGPoint(x: x(target.date), y: y(100))
                    context.fill(
                        Path(ellipseIn: CGRect(x: marker.x - 4, y: marker.y - 4, width: 8, height: 8)),
                        with: .color(Theme.danger)
                    )
                    // Two-sided clamp (Finding 2) — a fast-burn session can
                    // put marker.x near 0; the old clamp only capped the
                    // upper bound, clipping the label off the left edge.
                    let markerLabelPos = CGPoint(
                        x: max(min(marker.x, canvasSize.width - 48), 48), y: marker.y + 12
                    )
                    context.draw(
                        Text("EMPTY \(Format.time(target.date))")
                            .font(Theme.label(7.5))
                            .foregroundStyle(Theme.danger),
                        at: markerLabelPos
                    )
                    emptyMarkerLabelY = markerLabelPos.y
                    labelPositions.append(markerLabelPos)
                } else {
                    // Not actually running out: the projected segment answers
                    // this page's headline question ("will it last?") for the
                    // primary model, so it must read as at least as heavy as
                    // the alternates' own dashed lines (Finding 5) — was
                    // lineWidth 1.6 / Theme.coralDim (55% opacity), visually
                    // lighter than every alternate.
                    context.stroke(
                        projected,
                        with: .color(Theme.coral),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4])
                    )
                }
            }

            // Compute each alternate's polyline once, then sort by its
            // ending percent, descending. Higher percent maps to a smaller
            // y (higher on screen, see `y(_:)` above), and
            // nonCollidingLabelY only ever nudges DOWN — so processing
            // highest-percent-first means each subsequent, lower line only
            // ever gets pushed further down away from the ones already
            // placed above it, keeping the collision-nudge order matched
            // to the lines' actual top-to-bottom visual order instead of
            // inverting it.
            let alternatesWithPoints = alternates
                .map { ($0, alternatePolyline($0, visibleSamples: visible)) }
                .filter { $0.1.count > 1 }
                .sorted { ($0.1.last?.1 ?? 0) > ($1.1.last?.1 ?? 0) }

            // max(6, ...) guarantees upperBound >= lowerBound even when the
            // panel reports a degenerate height mid-expand/collapse
            // animation — a bare `6...(canvasSize.height - 6)` traps if
            // canvasSize.height < 12.
            let safeBounds: ClosedRange<CGFloat> = 6...max(6, canvasSize.height - 6)
            // Seeded with NOW's and (when drawn) the EMPTY marker's label
            // y-positions (Finding 3) — previously this started empty and
            // only ever accumulated alternate labels, leaving NOW/EMPTY
            // completely invisible to the collision check even though they
            // occupy the same space and can land within a few pixels of an
            // alternate's label.
            var placedLabelYs: [CGFloat] = [nowLabelY]
            if let emptyMarkerLabelY { placedLabelYs.append(emptyMarkerLabelY) }
            for (alternate, altPoints) in alternatesWithPoints {
                var altPath = Path()
                altPath.move(to: CGPoint(x: x(altPoints[0].0), y: y(altPoints[0].1)))
                for point in altPoints.dropFirst() {
                    altPath.addLine(to: CGPoint(x: x(point.0), y: y(point.1)))
                }
                let color = Theme.color(forModel: alternate.model)
                context.stroke(
                    altPath,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4])
                )
                if let end = altPoints.last {
                    let labelY = Self.nonCollidingLabelY(y(end.1), avoiding: placedLabelYs, minGap: 12, clampedTo: safeBounds)
                    placedLabelYs.append(labelY)
                    let dotX = drawEndLabel(
                        context: context,
                        x: x(end.0), y: labelY,
                        text: alternate.shortName, color: color,
                        canvasWidth: canvasSize.width
                    )
                    labelPositions.append(CGPoint(x: dotX, y: labelY))
                }
            }

            // "Now": vertical hairline + white dot, label above the dot.
            var nowLine = Path()
            nowLine.move(to: CGPoint(x: nowPoint.x, y: 0))
            nowLine.addLine(to: CGPoint(x: nowPoint.x, y: canvasSize.height))
            context.stroke(nowLine, with: .color(Theme.gridline), lineWidth: 1)
            context.fill(
                Path(ellipseIn: CGRect(x: nowPoint.x - 3.5, y: nowPoint.y - 3.5, width: 7, height: 7)),
                with: .color(Theme.marker)
            )
            let nowText = dominantModelShortName.map { "NOW · \($0.uppercased())" } ?? "NOW"
            let nowLabel = Text(nowText).font(Theme.label(7)).foregroundStyle(Theme.textDim)
            let resolvedNow = context.resolve(nowLabel)
            let nowTextSize = resolvedNow.measure(in: CGSize(width: 200, height: 20))
            let nowLabelX = min(
                max(nowPoint.x, nowTextSize.width / 2 + 4),
                canvasSize.width - nowTextSize.width / 2 - 4
            )
            context.draw(resolvedNow, at: CGPoint(x: nowLabelX, y: nowLabelY))
            labelPositions.append(CGPoint(x: nowLabelX, y: nowLabelY))

            drawScrubber(
                context: context, size: canvasSize, x: x, y: y,
                polyline: points, labelPositions: labelPositions
            )
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
        x: (Date) -> CGFloat, y: (Double) -> CGFloat,
        polyline points: [(date: Date, percent: Double, projected: Bool)],
        labelPositions: [CGPoint]
    ) {
        guard let hoverX, hoverX >= 0, hoverX <= size.width, !points.isEmpty else { return }
        let date = windowStart.addingTimeInterval(span * Double(hoverX / size.width))
        guard let value = interpolate(at: date, in: points) else { return }

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
        let bubbleHeight = textSize.height + 8
        let bubbleX = min(max(hoverX - bubbleWidth / 2, 4), size.width - bubbleWidth - 4)

        // Finding 4: the bubble used to always anchor near the top of the
        // canvas (y: 6), the same top-of-canvas band (y < 30) alternate/NOW/
        // EMPTY labels cluster in when percentages run high (y(percent) → 0
        // as percent → 100). An approximate check is enough here (not
        // pixel-perfect bounding boxes) — if any label sits roughly in the
        // bubble's x-range and that top band, drop the bubble to the
        // chart's vertical middle instead, where there's headroom.
        let topBandOccupied = labelPositions.contains { position in
            position.y < 30 && position.x >= bubbleX - 10 && position.x <= bubbleX + bubbleWidth + 10
        }
        let bubbleY: CGFloat = topBandOccupied ? max(size.height / 2 - bubbleHeight / 2, 30) : 6

        let bubble = CGRect(x: bubbleX, y: bubbleY, width: bubbleWidth, height: bubbleHeight)
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

    /// A small colored identity dot + the model's name in neutral text —
    /// text never carries the series color, only the dot does (see
    /// dataviz skill's "text never wears the data color" rule). Returns the
    /// dot's final x (for the caller's label-collision bookkeeping).
    ///
    /// The dot stays at the line's true endpoint `x`, only lightly clamped
    /// so the 5px-wide dot itself doesn't get cut off at the canvas edge
    /// (Finding 1) — the old clamp moved the DOT up to 44px inward to make
    /// room for the text, detaching it from the line it identifies in the
    /// common case (a line that won't cross 100% before the window resets)
    /// — exactly the "legend requiring color-matching at a distance"
    /// failure mode this feature's direct-label design exists to avoid.
    /// Only the TEXT repositions: it measures its own rendered width (like
    /// the "NOW" label already does) and flips to a trailing anchor, drawn
    /// to the LEFT of the dot, only when that still fits on-canvas —
    /// otherwise it stays leading, so a degenerate too-narrow canvas can't
    /// push the text off the opposite edge.
    @discardableResult
    private func drawEndLabel(
        context: GraphicsContext, x: CGFloat, y: CGFloat, text: String, color: Color, canvasWidth: CGFloat
    ) -> CGFloat {
        let dotX = min(x, canvasWidth - 3)
        context.fill(
            Path(ellipseIn: CGRect(x: dotX - 2.5, y: y - 2.5, width: 5, height: 5)),
            with: .color(color)
        )
        let label = Text(text.uppercased()).font(Theme.label(7.5)).foregroundStyle(Theme.textDim)
        let resolved = context.resolve(label)
        let textWidth = resolved.measure(in: CGSize(width: 200, height: 20)).width
        let fitsRight = dotX + 8 + textWidth <= canvasWidth
        let fitsLeft = dotX - 8 - textWidth >= 0
        if !fitsRight, fitsLeft {
            context.draw(resolved, at: CGPoint(x: dotX - 8, y: y), anchor: .trailing)
        } else {
            context.draw(resolved, at: CGPoint(x: dotX + 8, y: y), anchor: .leading)
        }
        return dotX
    }
}
