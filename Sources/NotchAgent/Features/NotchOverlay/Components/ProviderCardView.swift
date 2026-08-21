import SwiftUI

/// One provider inside the expanded notch panel, stick-style: giant
/// "% left" numeral, segmented tank meter, reset countdown.
struct ProviderCardView: View {
    let snapshot: UsageSnapshot?
    let provider: ProviderID
    let attention: AttentionLevel
    let refreshState: RefreshState
    var burn: BurnRate.Projection?

    @Environment(UsageStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let snapshot, snapshot.health.isUsable {
                metrics(snapshot)
            } else {
                unavailable
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassCard(cornerRadius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    attention == .normal ? .clear : attention.color.opacity(0.45),
                    lineWidth: 1
                )
        )
    }

    /// "~" prefix when the 5h percent is a local budget estimate, not the
    /// provider's authoritative quota.
    static func sessionPercentPrefix(_ snapshot: UsageSnapshot) -> String {
        snapshot.session?.usedPercentIsFromQuota == false ? "~" : ""
    }

    /// Fixed label for the TOP block — always the 5h session window.
    /// LAYOUT INVARIÁVEL (20/08/2026): the card always shows session above
    /// weekly; this label never switches windows (see
    /// QuotaHierarchyContractTests).
    static func sessionLabel(_ snapshot: UsageSnapshot) -> String {
        snapshot.session?.usedPercentIsFromQuota == false
            ? "OF 5H SESSION LEFT · ESTIMATED"
            : "OF 5H SESSION LEFT"
    }

    private var header: some View {
        HStack(spacing: 5) {
            providerGlyph
            GaugeLabel(text: provider.shortName, color: Theme.textSecondary, size: 9)
            Spacer()
            if let chip = quotaChip {
                StatusPill(text: chip.text, color: chip.color)
            }
        }
    }

    /// Brand glyph per provider: the Claude mascot (active model family) and
    /// the OpenAI knot, so the two cards are told apart at a glance. Both
    /// ride the same puppet — breathing, poke, hop, crush, shadow.
    @ViewBuilder
    private var providerGlyph: some View {
        switch provider {
        case .claudeCode:
            // 64pt: big enough for the blink/eye overlay to read.
            MascotPuppetView(spriteName: Self.mascotName(for: snapshot?.activeModel))
                .frame(width: 64, height: 64)
        case .codex:
            // The knot has no face, so no eyes — but every other
            // animation level (bob, poke, hop, crush, shadow) applies.
            MascotPuppetView(spriteName: "openai-glyph")
                .frame(width: 64, height: 64)
        default:
            Image(systemName: provider.symbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Maps an active model name to its mascot family asset; unknown or
    /// missing models fall back to sonnet.

    /// REGRESSÃO: with the probe on but no Claude Code OAuth on the
    /// machine, the probe delivers no quota and the card showed the raw
    /// token count as if it were the quota. When the probe is enabled and
    /// the snapshot carries no quota data, the card must say so instead.
    static func quotaUnavailable(
        for provider: ProviderID,
        probeEnabled: Bool,
        hasQuota: Bool
    ) -> Bool {
        provider == .claudeCode && probeEnabled && !hasQuota
    }

    static func mascotName(for model: String?) -> String {
        let families = ["fable", "opus", "haiku", "sonnet"]
        let lower = model?.lowercased() ?? ""
        for family in families where lower.contains(family) {
            return "claude-\(family)"
        }
        return "claude-sonnet"
    }

    private var quotaChip: (text: String, color: Color)? {
        switch snapshot?.quotaStatus {
        case .blocked: ("Blocked", Theme.danger)
        case .warning: ("Near limit", Theme.warning)
        default: nil
        }
    }

    @ViewBuilder
    private func metrics(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // LAYOUT INVARIÁVEL (20/08/2026): o bloco da sessão 5h SEMPRE
            // acima, o bloco da janela semanal SEMPRE abaixo — para Claude E
            // Codex, em qualquer estado de quota. Nunca um substitui o outro,
            // nunca um some. QuotaHierarchyContractTests lê este fonte e
            // exige essa ordem.
            sessionWindowBlock(snapshot)
            weeklyWindowBlock(snapshot)

            if let usage = usageLine(snapshot) {
                Text(usage)
                    .font(Theme.body(9.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
            if let hint = namedQuotaHint(snapshot) {
                Text(hint)
                    .font(Theme.body(8.5))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(2)
            } else {
                ForEach(namedQuotas(snapshot).prefix(2)) { quota in
                    namedQuotaLine(quota)
                }
            }
            if let verdict = BurnRate.verdict(burn) {
                Text(verdict)
                    .font(Theme.body(9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(burn?.exhaustsAt != nil ? Theme.warning : Theme.caution)
                    .lineLimit(1)
            }
            if snapshot.session?.usedPercent == nil, snapshot.weekly?.usedPercent == nil,
               let note = snapshot.note {
                Text(note)
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(2)
            }
        }
    }

    /// TOP block, always present: the 5h session window — official percent
    /// (or budget estimate marked "~"), else session tokens when the plan
    /// reports no daily cap, else an honest empty state.
    @ViewBuilder
    private func sessionWindowBlock(_ snapshot: UsageSnapshot) -> some View {
        let settings = store.settings
        if let percent = snapshot.session?.usedPercent {
            let tint = Theme.riskTint(
                used: percent,
                projectedToRunOut: burn?.exhaustsAt != nil,
                warningAt: settings.warningThresholdPercent,
                criticalAt: settings.criticalThresholdPercent
            )
            let prefix = Self.sessionPercentPrefix(snapshot)
            Text("\(prefix)\(Int(max(0, 100 - percent).rounded()))%")
                .font(Theme.numeral(30))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            GaugeLabel(text: Self.sessionLabel(snapshot))
            SegmentedMeter(percent: max(0, 100 - percent), segments: 12, tint: tint, height: 8)
            if let resets = snapshot.session?.resetsAt {
                VStack(alignment: .leading, spacing: 2) {
                    GaugeLabel(text: "RESETS • \(Format.time(resets))")
                    Text(Format.countdown(to: resets))
                        .font(Theme.body(15, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        } else if Self.quotaUnavailable(
            for: provider,
            probeEnabled: settings.claudeQuotaProbeEnabled,
            hasQuota: snapshot.quotaStatus != nil || snapshot.session?.usedPercentIsFromQuota == true
        ) {
            // The probe is on but no quota arrived (no Claude Code OAuth on
            // this machine) — honest "unavailable" beats a token count that
            // reads as the quota itself.
            Text("QUOTA INDISPONÍVEL")
                .font(Theme.numeral(18))
                .foregroundStyle(Theme.warning)
            GaugeLabel(text: "FAÇA LOGIN NO CLAUDE CODE PARA VER O %", color: Theme.textFaint, size: 8)
        } else if snapshot.session?.tokens.total ?? 0 > 0 {
            // Session with no daily cap reported (Codex plans that only
            // expose a weekly window): real session tokens, never a
            // fabricated percentage.
            Text(Format.tokens(snapshot.session!.tokens.total))
                .font(Theme.numeral(24))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            GaugeLabel(text: "CURRENT SESSION · NO DAILY CAP REPORTED")
            if let startedAt = snapshot.session?.startedAt {
                GaugeLabel(text: "STARTED \(Format.relative(startedAt))", color: Theme.textFaint, size: 8)
            }
        } else {
            Text("—")
                .font(Theme.numeral(24))
                .monospacedDigit()
                .foregroundStyle(Theme.textDim)
            GaugeLabel(text: "5H SESSION · NO DATA", color: Theme.textFaint, size: 8)
        }
    }

    /// BOTTOM block, always present: the weekly window.
    @ViewBuilder
    private func weeklyWindowBlock(_ snapshot: UsageSnapshot) -> some View {
        let settings = store.settings
        if let percent = snapshot.weekly?.usedPercent {
            weeklySecondaryBlock(
                secondary: (percent, snapshot.weekly?.resetsAt),
                warningAt: settings.warningThresholdPercent,
                criticalAt: settings.criticalThresholdPercent
            )
        } else {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("—")
                        .font(Theme.numeral(15))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textDim)
                    GaugeLabel(text: "OF WEEKLY LIMIT LEFT", color: Theme.textFaint, size: 8)
                    Spacer(minLength: 0)
                }
                SegmentedMeter(percent: 0, segments: 12, tint: Theme.textDim, height: 4)
            }
            .padding(.top, 1)
        }
    }

    /// Secondary scopes sharing the headline window (e.g. Codex's per-model
    /// weekly cap, Claude's Fable 5 pool) — most headroom FIRST. The
    /// headline number above already answers "am I in trouble"; this answers
    /// "where do I still have room to work", so it must surface what's still
    /// usable, not repeat the worst case.
    private func namedQuotas(_ snapshot: UsageSnapshot) -> [NamedQuota] {
        let quotas = snapshot.session?.namedQuotas ?? snapshot.weekly?.namedQuotas ?? []
        return quotas.sorted { $0.usedPercent < $1.usedPercent }
    }

    /// When every known scope is exhausted, listing them all at "0% left"
    /// answers nothing — point at where to actually check for a model with
    /// room, since a scope NotchAgent has never seen locally (never used
    /// this week) simply isn't in this data at all.
    private func namedQuotaHint(_ snapshot: UsageSnapshot) -> String? {
        Self.namedQuotaHintText(quotas: namedQuotas(snapshot), provider: snapshot.provider)
    }

    /// REGRESSÃO (21/08): with a single Codex model ever seen locally (the
    /// common case — most users only run one model), the generic "Every
    /// model seen locally..." wording reads as "the whole Codex account is
    /// exhausted", when it's really just that one model's weekly cap (the
    /// OpenAI account can still show other quotas at 100%). Naming the one
    /// scope that's actually exhausted removes the ambiguity; the generic
    /// wording is only correct once there's genuinely more than one.
    static func namedQuotaHintText(quotas: [NamedQuota], provider: ProviderID) -> String? {
        guard !quotas.isEmpty, quotas.allSatisfy({ $0.usedPercent >= 99.5 }) else { return nil }
        let portal = provider == .codex
            ? "chatgpt.com/codex/settings/usage"
            : "claude.ai/settings/usage"
        if quotas.count == 1, let only = quotas.first {
            return "\(only.name)'s weekly cap is exhausted · check \(portal) for other models"
        }
        return "Every model seen locally this week is exhausted · check \(portal) for one that isn't"
    }

    private func namedQuotaLine(_ quota: NamedQuota) -> some View {
        let remaining = max(0, 100 - quota.usedPercent)
        return HStack(spacing: 4) {
            Text(quota.name)
                .font(Theme.body(8.5))
                .foregroundStyle(Theme.textFaint)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(Int(remaining.rounded()))% left")
                .font(Theme.body(8.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.riskTint(
                    used: quota.usedPercent,
                    projectedToRunOut: false,
                    warningAt: store.settings.warningThresholdPercent,
                    criticalAt: store.settings.criticalThresholdPercent
                ))
        }
    }

    /// The weekly cap rendered as the bottom block — smaller scale of the
    /// session block above. Used only by `weeklyWindowBlock`.
    @ViewBuilder
    private func weeklySecondaryBlock(secondary: (usedPercent: Double, resetsAt: Date?), warningAt: Double, criticalAt: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            let tint = Theme.riskTint(
                used: secondary.usedPercent,
                projectedToRunOut: false,
                warningAt: warningAt,
                criticalAt: criticalAt
            )
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(Int(max(0, 100 - secondary.usedPercent).rounded()))%")
                    .font(Theme.numeral(15))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                GaugeLabel(text: "OF WEEKLY LIMIT LEFT", color: Theme.textFaint, size: 8)
                Spacer(minLength: 0)
            }
            SegmentedMeter(percent: max(0, 100 - secondary.usedPercent), segments: 12, tint: tint, height: 4)
            if let resets = secondary.resetsAt {
                HStack(spacing: 5) {
                    GaugeLabel(text: "RESETS • \(Format.time(resets))", color: Theme.textFaint, size: 8)
                    Text(Format.countdown(to: resets))
                        .font(Theme.body(12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.top, 1)
    }

    private func usageLine(_ snapshot: UsageSnapshot) -> String? {
        let metric = GaugeMetric.from(snapshot)
        let tokens: Int?
        let cost: CostEstimate?
        if metric?.isWeekly == true {
            tokens = snapshot.weekly?.tokens.total
            cost = snapshot.weekly?.cost
        } else {
            tokens = snapshot.session?.tokens.total
            cost = snapshot.session?.cost
        }
        var parts: [String] = []
        if let tokens, tokens > 0 {
            parts.append(Format.tokens(tokens))
        }
        if let cost, cost.amountUSD >= 0.01 {
            parts.append("~" + Format.usd(cost.amountUSD))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(snapshot?.health.badgeText ?? "Waiting for data…")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textDim)
            if let note = snapshot?.note {
                Text(note)
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(3)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let health = snapshot?.health {
                StatusPill(text: health.badgeText, color: healthColor(health))
            }
            Spacer()
            GaugeLabel(text: refreshText, color: Theme.textFaint, size: 8)
        }
    }

    private func healthColor(_ health: ProviderHealth) -> Color {
        switch health {
        case .ok: Theme.ok
        case .degraded, .parseError: Theme.warning
        case .notInstalled, .noData: Theme.textDim
        }
    }

    private var refreshText: String {
        switch refreshState {
        case .refreshing: "syncing…"
        case .success(let date): Format.relative(date)
        case .stale(let date): "stale \(Format.relative(date))"
        case .failure(let date, _): "failed \(Format.relative(date))"
        case .idle: ""
        }
    }
}
