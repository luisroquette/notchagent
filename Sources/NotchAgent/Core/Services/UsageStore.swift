import Foundation
import Observation

/// Single source of truth for the UI. All mutations happen on the main actor;
/// heavy work stays in providers and persistence actors.
@MainActor
@Observable
final class UsageStore {
    private(set) var snapshots: [ProviderID: UsageSnapshot] = [:]
    private(set) var refreshStates: [ProviderID: RefreshState] = [:]
    private(set) var events: [UsageEvent] = []
    private(set) var sparklines: [ProviderID: [Double]] = [:]
    /// Recent session-percent observations per provider, feeding burn-rate
    /// projections. In-memory only; trimmed to the last 6 hours.
    private(set) var percentHistory: [ProviderID: [PercentSample]] = [:]
    /// Unresolved incident from status.claude.com, when any.
    private(set) var activeIncident: String?
    /// Escalating "space left" alert currently taking over the notch panel.
    private(set) var activeThresholdAlert: ThresholdAlert?
    /// Fired sets are keyed per provider AND per window (session vs weekly):
    /// the gauge flipping between windows must not suppress nor re-fire alerts.
    @ObservationIgnored private var firedThresholds: [String: Set<Int>] = [:]
    @ObservationIgnored private var alertDismissTask: Task<Void, Never>?
    var isPaused = false

    let preferences: PreferencesStore
    /// Side-channel for system notifications; set once by AppEnvironment.
    @ObservationIgnored var onAlert: ((ProviderAlert) -> Void)?
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
    }

    func markRefreshing(_ provider: ProviderID) {
        refreshStates[provider] = .refreshing
    }

    func apply(_ snapshot: UsageSnapshot) {
        let alerts = StatusAggregator.transitionAlerts(old: snapshots, new: snapshot, settings: settings)
        snapshots[snapshot.provider] = snapshot
        refreshStates[snapshot.provider] = .success(snapshot.capturedAt)
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
    }

    func applyFailure(_ provider: ProviderID, error: String) {
        refreshStates[provider] = .failure(Date(), error)
        record(UsageEvent(provider: provider, kind: .error, level: .warning, message: error))
    }

    func record(_ event: UsageEvent) {
        events.insert(event, at: 0)
        if events.count > Self.maxEvents {
            events.removeLast(events.count - Self.maxEvents)
        }
    }

    func updateSparkline(_ provider: ProviderID, values: [Double]) {
        sparklines[provider] = values
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
        var fired = firedThresholds[key] ?? []

        if ThresholdAlerts.shouldReset(remaining: remaining) {
            fired = []
            // Window reset also clears a lingering takeover for this provider.
            if activeThresholdAlert?.provider == snapshot.provider {
                dismissThresholdAlert()
            }
        }
        if let threshold = ThresholdAlerts.newCrossing(remaining: remaining, alreadyFired: fired) {
            fired.formUnion(ThresholdAlerts.crossed(remaining: remaining))
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

    func setIncident(_ incident: String?) {
        guard incident != activeIncident else { return }
        activeIncident = incident
        if let incident {
            record(UsageEvent(kind: .alert, level: .warning, message: "Anthropic incident: \(incident)"))
        } else {
            record(UsageEvent(kind: .info, message: "Anthropic incident resolved"))
        }
    }
}
