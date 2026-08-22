import Foundation
import Observation

/// Single source of truth for the UI. All mutations happen on the main actor;
/// heavy work stays in providers and persistence actors.
@MainActor
@Observable
final class UsageStore {
    private(set) var snapshots: [ProviderID: UsageSnapshot] = [:]
    /// Payloads de insights por provider — a ÚNICA fronteira entre o motor e
    /// as views (notch/painel/notificação renderizam, nunca recalculam).
    private(set) var sessionPayloads: [ProviderID: SessionInsightsPayload] = [:]
    private(set) var refreshStates: [ProviderID: RefreshState] = [:]
    private(set) var accountRefreshStates: [UUID: RefreshState] = [:]
    private(set) var events: [UsageEvent] = []
    private(set) var sparklines: [ProviderID: [Double]] = [:]
    /// Recent session-percent observations per provider, feeding burn-rate
    /// projections. In-memory only; trimmed to the last 6 hours.
    private(set) var percentHistory: [ProviderID: [PercentSample]] = [:]
    /// Unresolved incident from status.claude.com, when any.
    private(set) var activeIncident: String?
    /// Escalating "space left" alert currently taking over the notch panel.
    private(set) var activeThresholdAlert: ThresholdAlert?
    /// Positive counterpart: shown once when a provider unblocks mid-work.
    private(set) var activeRestoreMoment: RestoreMoment?
    /// Fired sets are keyed per provider AND per window (session vs weekly):
    /// the gauge flipping between windows must not suppress nor re-fire alerts.
    @ObservationIgnored private var firedThresholds: [String: Set<Int>] = [:]
    /// Deepest point reached while `firedThresholds[key]` is non-empty — the
    /// animation's starting point once the window resets and we celebrate.
    @ObservationIgnored private var lowestRemainingSinceFired: [String: Double] = [:]
    /// Authoritative window boundary when providers expose one. This avoids
    /// treating ordinary quota-estimate corrections as a new window.
    @ObservationIgnored private var alertWindowResetAt: [String: Date] = [:]
    @ObservationIgnored private var alertDismissTask: Task<Void, Never>?
    @ObservationIgnored private var restoreDismissTask: Task<Void, Never>?
    /// REGRESSÃO (22/08): `firedThresholds` is intentionally keyed per
    /// provider+window (session vs weekly) — a real design choice (see that
    /// property's comment) so a gauge flipping windows never suppresses nor
    /// re-fires a genuine alert. But a provider whose GaugeMetric.isWeekly
    /// itself flips true/false refresh-to-refresh (Codex, since
    /// CodexProvider.primaryWeeklyScope started picking the model with the
    /// MOST headroom — weekly is no longer always exhausted) mints a "new"
    /// key on every flip, and the OTHER key's stale fired state looks like a
    /// fresh reset on the very next flip back. Without a floor, that
    /// alternation celebrates (and force-expands the panel) every few
    /// minutes with no real quota reset. This cooldown is additive — it
    /// doesn't touch the per-window key design, it just stops the SAME
    /// provider from celebrating twice in a row faster than a real reset
    /// could plausibly happen.
    private static let restoreCooldown: TimeInterval = 20 * 60
    @ObservationIgnored private var lastRestoreAt: [ProviderID: Date] = [:]
    var isPaused = false {
        didSet { if oldValue != isPaused { onDeskStateChange?() } }
    }

    let preferences: PreferencesStore
    /// Side-channel for system notifications; set once by AppEnvironment.
    @ObservationIgnored var onAlert: ((ProviderAlert) -> Void)?
    @ObservationIgnored var onRestore: ((RestoreMoment) -> Void)?
    /// Coalesced by NotchAgentDeskCoordinator; contains no transport logic.
    @ObservationIgnored var onDeskStateChange: (() -> Void)?
    private static let maxEvents = 200

    init(preferences: PreferencesStore) {
        self.preferences = preferences
    }

    var settings: AppSettings { preferences.settings }

    var overallAttention: AttentionLevel {
        StatusAggregator.overallAttention(snapshots: snapshots, settings: settings)
    }

    var primaryProvider: ProviderID? {
        StatusAggregator.primaryProvider(snapshots: snapshots, settings: settings)
    }

    var primarySnapshot: UsageSnapshot? {
        primaryProvider.flatMap { snapshots[$0] }
    }

    func attention(for provider: ProviderID) -> AttentionLevel {
        snapshots[provider].map { StatusAggregator.attention(for: $0, settings: settings) } ?? .normal
    }

    func restore(_ persisted: [ProviderID: UsageSnapshot]) {
        for (provider, snapshot) in persisted where snapshots[provider] == nil {
            snapshots[provider] = snapshot
        }
        onDeskStateChange?()
    }

    func setPayloads(_ payloads: [ProviderID: SessionInsightsPayload]) {
        sessionPayloads = payloads
    }

    func markRefreshing(_ provider: ProviderID) {
        refreshStates[provider] = .refreshing
        if provider == .apiAccounts {
            for account in settings.apiAccounts where account.enabled {
                accountRefreshStates[account.id] = .refreshing
            }
        }
        onDeskStateChange?()
    }

    func markAccountRefreshing(_ accountID: UUID) {
        accountRefreshStates[accountID] = .refreshing
        onDeskStateChange?()
    }

    func apply(_ snapshot: UsageSnapshot, updatingAccountIDs: Set<UUID>? = nil) {
        let alerts = StatusAggregator.transitionAlerts(old: snapshots, new: snapshot, settings: settings)
        snapshots[snapshot.provider] = snapshot
        refreshStates[snapshot.provider] = .success(snapshot.capturedAt)
        if snapshot.provider == .apiAccounts {
            for usage in snapshot.accountUsage ?? []
            where updatingAccountIDs?.contains(usage.accountID) ?? true {
                let date = usage.capturedAt ?? snapshot.capturedAt
                switch usage.readStatus {
                case .updated, .partial:
                    accountRefreshStates[usage.accountID] = .success(date)
                case .stale:
                    accountRefreshStates[usage.accountID] = .stale(date)
                case .needsCredential, .needsLogin, .unavailable:
                    accountRefreshStates[usage.accountID] = .failure(date, usage.summary)
                case nil:
                    accountRefreshStates[usage.accountID] = .failure(date, "Leitura sem estado")
                }
            }
        }
        if let percent = snapshot.session?.usedPercent {
            var samples = percentHistory[snapshot.provider] ?? []
            samples.append(PercentSample(date: snapshot.capturedAt, percent: percent))
            let cutoff = Date().addingTimeInterval(-6 * 3600)
            samples.removeAll { $0.date < cutoff }
            percentHistory[snapshot.provider] = samples
        }
        processThresholds(snapshot)
        for alert in alerts {
            record(UsageEvent(
                date: alert.date,
                provider: alert.provider,
                kind: .alert,
                level: alert.level,
                message: alert.message
            ))
            onAlert?(alert)
        }
        onDeskStateChange?()
    }

    func applyFailure(
        _ provider: ProviderID,
        error: String,
        updatingAccountIDs: Set<UUID>? = nil
    ) {
        refreshStates[provider] = .failure(Date(), error)
        if provider == .apiAccounts {
            for account in settings.apiAccounts
            where account.enabled && (updatingAccountIDs?.contains(account.id) ?? true) {
                accountRefreshStates[account.id] = .failure(Date(), error)
            }
        }
        record(UsageEvent(provider: provider, kind: .error, level: .warning, message: error))
        onDeskStateChange?()
    }

    func accountRefreshState(
        _ accountID: UUID,
        now: Date = Date(),
        staleAfter: TimeInterval? = nil
    ) -> RefreshState {
        let state = accountRefreshStates[accountID] ?? .idle
        guard case .success(let date) = state else { return state }
        let threshold = staleAfter ?? max(settings.refreshIntervalSeconds * 3, 20 * 60)
        return now.timeIntervalSince(date) > threshold ? .stale(date) : state
    }

    func record(_ event: UsageEvent) {
        events.insert(event, at: 0)
        if events.count > Self.maxEvents {
            events.removeLast(events.count - Self.maxEvents)
        }
    }

    func updateSparkline(_ provider: ProviderID, values: [Double]) {
        sparklines[provider] = values
        onDeskStateChange?()
    }

    var recentErrors: [UsageEvent] {
        Array(events.filter { $0.kind == .error }.prefix(5))
    }

    func burnProjection(for provider: ProviderID) -> BurnRate.Projection? {
        BurnRate.project(
            samples: percentHistory[provider] ?? [],
            resetsAt: snapshots[provider]?.session?.resetsAt
        )
    }

    private func processThresholds(_ snapshot: UsageSnapshot) {
        // A transient snapshot without a gauge keeps the fired sets intact —
        // resetting here would re-fire (and re-notify) already-seen crossings.
        guard let metric = GaugeMetric.from(snapshot) else { return }
        let remaining = metric.remaining
        let key = "\(snapshot.provider.rawValue)·\(metric.isWeekly ? "wk" : "5h")"
        let configuredThresholds = ThresholdAlerts.normalized(settings.quotaAlertThresholdPercents)
        guard !configuredThresholds.isEmpty else {
            firedThresholds[key] = []
            lowestRemainingSinceFired[key] = nil
            return
        }
        let resetAt = metric.isWeekly ? snapshot.weekly?.resetsAt : snapshot.session?.resetsAt
        let isFirstObservation = firedThresholds[key] == nil
        var fired = firedThresholds[key] ?? []
        let resetBoundaryChanged = ThresholdAlerts.resetBoundaryChanged(
            previous: alertWindowResetAt[key],
            current: resetAt
        )
        let inferredReset = resetAt == nil && ThresholdAlerts.shouldReset(
            remaining: remaining,
            previousLow: lowestRemainingSinceFired[key]
        )
        if !isFirstObservation && (resetBoundaryChanged || inferredReset) {
            // Had crossed into low-fuel territory and just climbed back out —
            // celebrate it, using the deepest point reached as the animation's
            // starting fuel level. Covers a window resetting on schedule, an
            // API block clearing, or credits topping up — they all look the
            // same from here: fired was non-empty, now the tank is fine. Still
            // gated on recent activity: no celebration for "picked the Mac up
            // three days later and it had reset ages ago."
            if !fired.isEmpty, let low = lowestRemainingSinceFired[key],
               let lastActivity = snapshot.lastActivityAt,
               snapshot.capturedAt.timeIntervalSince(lastActivity) < 10 * 60 {
                presentRestore(provider: snapshot.provider, previousRemaining: low, remaining: remaining, isWeekly: metric.isWeekly, now: snapshot.capturedAt)
            }
            fired = []
            lowestRemainingSinceFired[key] = nil
            // Window reset also clears a lingering takeover for this provider.
            if activeThresholdAlert?.provider == snapshot.provider {
                dismissThresholdAlert()
            }
        }
        if let resetAt { alertWindowResetAt[key] = resetAt }
        let threshold = isFirstObservation
            ? ThresholdAlerts.initialCrossing(remaining: remaining, levels: configuredThresholds)
            : ThresholdAlerts.newCrossing(remaining: remaining, alreadyFired: fired, levels: configuredThresholds)
        if let threshold {
            fired.formUnion(ThresholdAlerts.crossed(
                remaining: remaining,
                levels: configuredThresholds
            ))
            let alert = ThresholdAlert(
                provider: snapshot.provider,
                threshold: threshold,
                remaining: remaining,
                isWeekly: metric.isWeekly
            )
            present(alert)
            let level = ThresholdAlerts.attentionLevel(for: threshold)
            let message = ThresholdAlerts.message(for: alert)
            record(UsageEvent(provider: snapshot.provider, kind: .alert, level: level, message: message))
            onAlert?(ProviderAlert(provider: snapshot.provider, level: level, message: message))
        }
        if isFirstObservation {
            fired.formUnion(ThresholdAlerts.crossed(remaining: remaining, levels: configuredThresholds))
        }
        if !fired.isEmpty {
            lowestRemainingSinceFired[key] = min(lowestRemainingSinceFired[key] ?? remaining, remaining)
        }
        firedThresholds[key] = fired
    }

    /// Severity-aware takeover: a sticky 5% moment is never replaced by a
    /// milder crossing from another provider in the same refresh cycle.
    private func present(_ alert: ThresholdAlert) {
        if let current = activeThresholdAlert, current.threshold < alert.threshold {
            return
        }
        activeThresholdAlert = alert
        // Auto-dismiss lives in the STORE, not the view — collapsing the panel
        // mid-countdown must not orphan a stale alert for hours (review finding).
        alertDismissTask?.cancel()
        guard alert.threshold > 5 else { return }
        alertDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled else { return }
            if self?.activeThresholdAlert == alert {
                self?.dismissThresholdAlert()
            }
        }
    }

    func dismissThresholdAlert() {
        alertDismissTask?.cancel()
        alertDismissTask = nil
        activeThresholdAlert = nil
    }

    /// Sticky like `present(_:)`: a moment already showing isn't replaced by a
    /// smaller bounce-back from another provider in the same refresh cycle.
    private func presentRestore(provider: ProviderID, previousRemaining: Double, remaining: Double, isWeekly: Bool, now: Date) {
        if let last = lastRestoreAt[provider], now.timeIntervalSince(last) < Self.restoreCooldown {
            return
        }
        lastRestoreAt[provider] = now
        let moment = RestoreMoment(
            provider: provider,
            previousRemaining: previousRemaining,
            remaining: remaining,
            isWeekly: isWeekly
        )
        activeRestoreMoment = moment
        restoreDismissTask?.cancel()
        restoreDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5.5))
            guard !Task.isCancelled else { return }
            if self?.activeRestoreMoment == moment {
                self?.dismissRestoreMoment()
            }
        }
        record(UsageEvent(provider: provider, kind: .info, message: moment.message))
        onRestore?(moment)
    }

    func dismissRestoreMoment() {
        restoreDismissTask?.cancel()
        restoreDismissTask = nil
        activeRestoreMoment = nil
    }

    func setIncident(_ incident: String?) {
        guard incident != activeIncident else { return }
        activeIncident = incident
        if let incident {
            record(UsageEvent(kind: .alert, level: .warning, message: "Anthropic incident: \(incident)"))
        } else {
            record(UsageEvent(kind: .info, message: "Anthropic incident resolved"))
        }
        onDeskStateChange?()
    }
}
