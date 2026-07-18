import SwiftUI
import AgentMeterCore

/// Expanded gauge panel: stick-style pager with NOW / BURN / RHYTHM pages.
struct NotchExpandedView: View {
    @Environment(UsageStore.self) private var store
    @Environment(NotchViewModel.self) private var viewModel
    @Environment(WindowRouter.self) private var router
    @EnvironmentObject private var spending: SubscriptionStore

    @State private var rhythmToday = false

    var body: some View {
        @Bindable var viewModel = viewModel

        TimelineView(.periodic(from: .now, by: 30)) { _ in
            VStack(spacing: 10) {
                header
                coralRule
                if let incident = store.activeIncident {
                    incidentLine(incident)
                }
                ZStack {
                    Group {
                        switch viewModel.expandedPage {
                        case 1: burnPage
                        case 2: rhythmPage
                        case 3: modelsPage
                        case 4: gptModelsPage
                        default: nowPage
                        }
                    }
                    .id(viewModel.expandedPage)
                    .transition(.asymmetric(
                        insertion: .move(edge: viewModel.pageDirection).combined(with: .opacity),
                        removal: .move(edge: viewModel.pageDirection == .trailing ? .leading : .trailing)
                            .combined(with: .opacity)
                    ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                footer
                // The dino-game strip doubles as the panel's ground line;
                // difficulty tracks the real session gauge.
                if store.settings.runnerEnabled {
                    let game = store.runnerGame
                    NotchRunnerView(
                        usedPercent: game.used,
                        isGameOver: game.gameOver,
                        resetsAt: game.resetsAt,
                        obstacleTint: game.obstacleTint
                    )
                    .frame(height: 26)
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, viewModel.geometry.hasNotch ? viewModel.geometry.topInset + 6 : 12)
            .padding(.bottom, 12)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            PixelGlyph(distress: distress)
                .frame(width: 22, height: 18)
            Text("NOTCHAGENT")
                .font(Theme.label(11))
                .kerning(2)
                .foregroundStyle(Theme.coral)
            Spacer()
            if store.isPaused {
                StatusPill(text: "Paused", color: Theme.warning)
            }
            Button {
                router.openSpending()
            } label: {
                GaugeLabel(text: "PAGO " + spending.format(spending.monthlySpend.paidBRL, compact: true), color: Theme.coral, size: 8)
            }
            .buttonStyle(.plain)
            .help("Gasto confirmado neste mês")
            GaugeLabel(text: updatedText, color: Theme.textFaint, size: 8)
            Button {
                viewModel.togglePin()
            } label: {
                Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(viewModel.isPinned ? Theme.coral : Theme.textDim)
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.surfaceRaised))
            }
            .buttonStyle(.plain)
            .help(viewModel.isPinned ? "Unpin panel" : "Keep panel open")
        }
    }

    /// The mascot sweats as the busiest window drains.
    private var distress: Double {
        let worstUsed = ProviderID.allCases
            .compactMap { GaugeMetric.from(store.snapshots[$0])?.used }
            .max() ?? 0
        return worstUsed / 100
    }

    private var updatedText: String {
        let lastSuccess = store.refreshStates.values
            .compactMap { state -> Date? in
                if case .success(let date) = state { date } else { nil }
            }
            .max()
        guard let lastSuccess else { return "waiting…" }
        return "updated \(Format.relative(lastSuccess))"
    }

    private var coralRule: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Theme.coral, Theme.coral.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 2)
    }

    private func incidentLine(_ incident: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(Theme.warning)
            Text("Anthropic incident: \(incident)")
                .font(Theme.body(9.5, weight: .semibold))
                .foregroundStyle(Theme.warning)
                .lineLimit(1)
            Spacer()
        }
    }

    // MARK: Pages

    /// Claude Code and Codex always keep equal, detailed cards. A temporary
    /// quota-probe failure must not collapse Claude into a status strip.
    private var nowPage: some View {
        let cardProviders: [ProviderID] = [.claudeCode, .codex]
        let stripProviders = ProviderID.allCases.filter { !cardProviders.contains($0) }

        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                ForEach(cardProviders) { provider in
                    ProviderCardView(
                        snapshot: store.snapshots[provider],
                        provider: provider,
                        attention: store.attention(for: provider),
                        refreshState: store.refreshStates[provider] ?? .idle,
                        burn: store.burnProjection(for: provider)
                    )
                }
            }
            .frame(maxHeight: .infinity)
            ForEach(stripProviders) { provider in
                providerStrip(provider)
            }
        }
    }

    private func providerStrip(_ provider: ProviderID) -> some View {
        let snapshot = store.snapshots[provider]
        return HStack(spacing: 8) {
            Image(systemName: provider.symbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textDim)
            GaugeLabel(text: provider.shortName, color: Theme.textSecondary, size: 9)
            if let health = snapshot?.health {
                StatusPill(text: health.badgeText, color: health == .ok ? Theme.ok : Theme.textDim)
            }
            if let note = snapshot?.note {
                Text(note)
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.surface.opacity(0.7))
        )
    }

    /// Answers ONE question: "will I run out before the reset?"
    private var burnPage: some View {
        let focus = viewModel.focusProvider
        let snapshot = store.snapshots[focus]
        let session = snapshot?.session
        let end = session?.resetsAt ?? Date()
        let start = session?.startedAt ?? end.addingTimeInterval(-5 * 3600)
        let samples = store.percentHistory[focus] ?? []
        let projection = store.burnProjection(for: focus)
        let used = session?.usedPercent
        let verdict = burnVerdict(projection: projection, hasSamples: !samples.isEmpty)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    GaugeLabel(text: "BURN · WILL THE 5H SESSION LAST?", color: Theme.textSecondary, size: 9)
                    if let used {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(Int((100 - used).rounded()))%")
                                .font(Theme.numeral(24))
                                .monospacedDigit()
                                .foregroundStyle(Theme.riskTint(
                                    used: used,
                                    projectedToRunOut: projection?.exhaustsAt != nil,
                                    warningAt: store.settings.warningThresholdPercent,
                                    criticalAt: store.settings.criticalThresholdPercent
                                ))
                            GaugeLabel(text: "LEFT", color: Theme.textDim, size: 8)
                            if let resets = session?.resetsAt {
                                GaugeLabel(
                                    text: "· RESETS \(Format.time(resets)) · IN \(Format.countdown(to: resets))",
                                    color: Theme.textFaint,
                                    size: 8
                                )
                            }
                        }
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(burnProviders) { provider in
                        selectorChip(provider.shortName, active: provider == focus) {
                            viewModel.focusProvider = provider
                        }
                    }
                }
            }

            Text(verdict.text)
                .font(Theme.body(11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(verdict.color)
                .lineLimit(1)

            BurnChartView(
                samples: samples,
                projection: projection,
                windowStart: start,
                windowEnd: end
            )
            .frame(maxHeight: .infinity)

            GaugeLabel(
                text: "SOLID = REAL USAGE · DOTTED = PROJECTION AT CURRENT PACE",
                color: Theme.textFaint,
                size: 7
            )
        }
    }

    private func burnVerdict(
        projection: BurnRate.Projection?,
        hasSamples: Bool
    ) -> (text: String, color: Color) {
        if let text = BurnRate.verdict(projection) {
            return (text, projection?.exhaustsAt != nil ? Theme.warning : Theme.caution)
        }
        if hasSamples {
            return ("No burn right now — safe until the reset.", Theme.ok)
        }
        return ("Collecting samples — verdict appears after a few minutes of use.", Theme.textDim)
    }

    private var burnProviders: [ProviderID] {
        let withSamples = ProviderID.allCases.filter { !(store.percentHistory[$0] ?? []).isEmpty }
        return withSamples.isEmpty ? [.claudeCode] : withSamples
    }

    /// Answers ONE question: "when do I burn the most?"
    private var rhythmPage: some View {
        let totals = rhythmTotals
        let total = totals.reduce(0, +)
        let peak = totals.enumerated().max { $0.element < $1.element }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    GaugeLabel(text: "RHYTHM · WHEN DO YOU BURN THE MOST?", color: Theme.textSecondary, size: 9)
                    if let peak, peak.element > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(peak.offset)h")
                                .font(Theme.numeral(24))
                                .monospacedDigit()
                                .foregroundStyle(Theme.coral)
                            GaugeLabel(text: "PEAK HOUR", color: Theme.textDim, size: 8)
                            GaugeLabel(
                                text: "· \(Format.tokens(total)) TOKENS \(rhythmToday ? "TODAY" : "IN 7 DAYS")",
                                color: Theme.textFaint,
                                size: 8
                            )
                        }
                    } else {
                        Text("No activity recorded \(rhythmToday ? "today" : "this week") yet.")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    selectorChip("Today", active: rhythmToday) { rhythmToday = true }
                    selectorChip("7 days", active: !rhythmToday) { rhythmToday = false }
                }
            }
            RhythmChartView(totals: totals)
                .frame(maxHeight: .infinity)
            GaugeLabel(text: "TOKENS BURNED PER LOCAL HOUR · WHITE = CURRENT HOUR", color: Theme.textFaint, size: 7)
        }
    }

    private var rhythmTotals: [Int] {
        var totals = [Int](repeating: 0, count: 24)
        let dayStart = Date().flooredToDay
        for snapshot in store.snapshots.values {
            for entry in snapshot.weekly?.hourlyTotals ?? [] {
                if rhythmToday && entry.hour < dayStart { continue }
                totals[Calendar.current.component(.hour, from: entry.hour)] += entry.tokens
            }
        }
        return totals
    }

    // MARK: Models page

    private static let modelFamilies: [(key: String, name: String)] = [
        ("haiku", "Haiku"), ("sonnet", "Sonnet"), ("opus", "Opus"), ("fable", "Fable"),
    ]

    private var modelsPage: some View {
        let snapshot = store.snapshots[.claudeCode]
        let health = snapshot?.modelHealth ?? []
        let breakdown = snapshot?.modelBreakdown ?? []

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                GaugeLabel(text: "CLAUDE MODELS", color: Theme.textSecondary, size: 9)
                Spacer()
                GaugeLabel(text: "LIVE PROBE · 1 MODEL / CYCLE", color: Theme.textFaint, size: 7)
            }
            HStack(spacing: 10) {
                ForEach(Self.modelFamilies, id: \.key) { family in
                    modelCard(
                        family: family,
                        health: health.first { $0.model.contains(family.key) },
                        usage: familyUsage(family.key, breakdown: breakdown)
                    )
                }
            }
            .frame(maxHeight: .infinity)
            GaugeLabel(
                text: health.isEmpty
                    ? "ENABLE THE API PROBE IN SETTINGS FOR LIVE STATUS"
                    : "USAGE FROM LOCAL TRANSCRIPTS · LAST 7 DAYS",
                color: Theme.textFaint,
                size: 7.5
            )
        }
    }

    private func familyUsage(_ key: String, breakdown: [ModelUsage]) -> (tokens: Int, cost: Double)? {
        let matches = breakdown.filter { $0.model.contains(key) }
        guard !matches.isEmpty else { return nil }
        return (matches.reduce(0) { $0 + $1.tokens }, matches.reduce(0) { $0 + $1.costUSD })
    }

    private func modelCard(
        family: (key: String, name: String),
        health: ModelHealth?,
        usage: (tokens: Int, cost: Double)?
    ) -> some View {
        VStack(spacing: 7) {
            PixelGlyph(
                tint: health?.status == .error ? Theme.textDim : Theme.coral,
                distress: health?.status == .limited ? 0.7 : 0
            )
            .frame(width: 46, height: 36)
            Text(family.name)
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            modelStatusPill(health)
            if let usage {
                GaugeLabel(
                    text: "\(Format.tokens(usage.tokens))\(usage.cost >= 0.01 ? " · ~" + Format.usd(usage.cost) : "")",
                    color: Theme.textDim,
                    size: 7.5
                )
            } else {
                GaugeLabel(text: "NO RECENT USE", color: Theme.textFaint, size: 7.5)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface)
        )
    }

    @ViewBuilder
    private func modelStatusPill(_ health: ModelHealth?) -> some View {
        switch health?.status {
        case .ok:
            StatusPill(
                text: health?.latencyMs.map { String(format: "OK %.1fs", Double($0) / 1000) } ?? "OK",
                color: Theme.ok
            )
        case .limited:
            StatusPill(text: "Limited", color: Theme.caution)
        case .error:
            StatusPill(text: "Error", color: Theme.danger)
        case nil:
            StatusPill(text: "N/D", color: Theme.textDim)
        }
    }

    // MARK: OpenAI models page

    /// Per-model usage from Codex rollouts. OpenAI exposes no per-model quota
    /// locally, so this page reports real consumption share — never fake limits.
    private var gptModelsPage: some View {
        let snapshot = store.snapshots[.codex]
        let breakdown = snapshot?.modelBreakdown ?? []
        let totalTokens = max(breakdown.reduce(0) { $0 + $1.tokens }, 1)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    GaugeLabel(text: "OPENAI MODELS · WHERE DO CODEX TOKENS GO?", color: Theme.textSecondary, size: 9)
                    if let top = breakdown.first {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(top.model)
                                .font(Theme.numeral(19))
                                .foregroundStyle(Theme.coral)
                                .lineLimit(1)
                            GaugeLabel(
                                text: "TOP MODEL · \(Int(Double(top.tokens) / Double(totalTokens) * 100))% OF TOKENS",
                                color: Theme.textDim,
                                size: 8
                            )
                        }
                    } else {
                        Text("No Codex sessions in the last 7 days.")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                Spacer()
                if let note = snapshot?.note {
                    StatusPill(text: note, color: Theme.textSecondary)
                }
            }

            VStack(spacing: 6) {
                ForEach(breakdown.prefix(5)) { usage in
                    modelUsageRow(usage, share: Double(usage.tokens) / Double(totalTokens))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            GaugeLabel(
                text: "LAST 7 DAYS · LOCAL ROLLOUTS · OPENAI EXPOSES NO PER-MODEL LIMITS",
                color: Theme.textFaint,
                size: 7
            )
        }
    }

    private func modelUsageRow(_ usage: ModelUsage, share: Double) -> some View {
        HStack(spacing: 10) {
            Text(usage.model)
                .font(Theme.body(11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            SegmentedMeter(percent: share * 100, segments: 16, tint: Theme.coral.opacity(0.9), height: 6)
            Text("\(Format.tokens(usage.tokens))\(usage.costUSD >= 0.01 ? " · ~" + Format.usd(usage.costUSD) : "")")
                .font(Theme.body(9.5))
                .monospacedDigit()
                .foregroundStyle(Theme.textDim)
                .frame(width: 118, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.surface)
        )
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            actionChip("arrow.clockwise", "Refresh") {
                AppEnvironment.shared.scheduler.refreshNow()
            }
            actionChip(store.isPaused ? "play.fill" : "pause.fill", store.isPaused ? "Resume" : "Pause") {
                store.isPaused.toggle()
            }
            Spacer()
            PagerDots(
                page: Binding(
                    get: { viewModel.expandedPage },
                    set: { viewModel.goToPage($0) }
                ),
                count: NotchViewModel.pageCount
            )
            Spacer()
            actionChip("chart.bar.xaxis", "Dashboard") {
                router.openDashboard()
            }
            actionChip("gearshape", "Settings") {
                router.openSettings()
            }
        }
    }

    private func selectorChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(9.5, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(active ? Theme.coral : Theme.surfaceRaised))
                .foregroundStyle(active ? Color.black.opacity(0.85) : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func actionChip(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(Theme.body(10, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.surfaceRaised))
            .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }
}
