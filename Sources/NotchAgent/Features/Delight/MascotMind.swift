import Foundation
import Observation

/// The mascot's running mind: owns the persisted state, ticks every 60s,
/// derives CONTEXT from app events (expand, peak passed, quota reset,
/// midnight) and publishes contextual animation requests. Variety is
/// deterministic round-robin per context — never a coin flip.
/// Everything here is gated by `settings.delightEnabled`.
@MainActor
@Observable
public final class MascotMind {
    public private(set) var state: MascotMindState
    /// The latest published animation request; the puppet plays these.
    public private(set) var animationRequest: AnimationRequest?

    private let persistence: MascotMindPersistence
    private let settings: PreferencesStore
    private weak var store: UsageStore?
    private var tickTask: Task<Void, Never>?
    private var lastTickAt = Date()
    private var lastInteractionAt = Date()
    private var burnHigh = false
    private var previousMetrics: [ProviderID: GaugeMetric] = [:]
    private var requestID = 0

    init(
        settings: PreferencesStore,
        store: UsageStore,
        persistence: MascotMindPersistence = MascotMindPersistence()
    ) {
        self.settings = settings
        self.store = store
        self.persistence = persistence
        self.state = persistence.load()
    }

    public func start() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.tick()
            }
        }
    }

    public func stop() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// Called when the panel expands. The first expand of the day greets;
    /// every other expand plays the mood's context — always an animation,
    /// always contextual, never the same variant twice in a row.
    public func noteExpanded(now: Date = Date()) {
        lastInteractionAt = now
        guard settings.settings.delightEnabled else { return }
        let first = MascotMindCore.firstExpandOfDay(state: state, dayKey: DelightSignals.dayKey(now))
        if first {
            state.lastExpandedDay = DelightSignals.dayKey(now)
            state.affection = min(1, state.affection + DelightCatalog.affectionBump(firstExpandOfDay: true))
        }
        let context = DelightCatalog.expandContext(mood: state.mood, firstExpandOfDay: first)
        let bob = DelightCatalog.selectBob(context: context, cursor: &state.variantCursor)
        publish(context: context, bob: bob)
        saveSoon()
    }

    /// Called when the panel collapses.
    public func noteCollapsed(now: Date = Date()) {
        lastInteractionAt = now
    }

    /// The user touched the mascot — displeasure, always, with variety.
    public func notePoked(now: Date = Date()) {
        lastInteractionAt = now
        guard settings.settings.delightEnabled else { return }
        let poke = DelightCatalog.selectPoke(cursor: &state.variantCursor)
        publish(context: .poke, poke: poke)
        saveSoon()
    }

    /// The usage peak passed (alert cleared) — relief.
    public func notePeakPassed(now: Date = Date()) {
        guard settings.settings.delightEnabled else { return }
        let bob = DelightCatalog.selectBob(context: .relief, cursor: &state.variantCursor)
        publish(context: .relief, bob: bob)
        saveSoon()
    }

    private func tick() {
        guard settings.settings.delightEnabled else { return }
        let now = Date()
        let idle = now.timeIntervalSince(lastInteractionAt)

        var s = state
        MascotMindCore.evolveTick(state: &s, now: now, idleSeconds: idle, burnHigh: burnHigh)
        if let lastSeen = state.lastSeen {
            let absentDays = max(0, Int(now.timeIntervalSince(lastSeen) / 86_400))
            s.affection = max(0, s.affection - DelightCatalog.affectionAbsencePenalty(absentDays: absentDays))
        }
        state = s

        detectQuotaReset(now: now)

        if DelightSignals.crossedMidnight(previous: lastTickAt, now: now) {
            let bob = DelightCatalog.selectBob(context: .midnightMoment, cursor: &state.variantCursor)
            publish(context: .midnightMoment, bob: bob)
        }
        lastTickAt = now
        saveSoon()
    }

    private func detectQuotaReset(now: Date) {
        guard let snapshots = store?.snapshots else { return }
        var currentMetrics: [ProviderID: GaugeMetric] = [:]
        for (provider, snapshot) in snapshots {
            if let metric = GaugeMetric.from(snapshot) {
                currentMetrics[provider] = metric
            }
        }
        let resetProviders = currentMetrics.keys.filter {
            DelightSignals.quotaResetDetected(previous: previousMetrics[$0], current: currentMetrics[$0])
        }
        if !resetProviders.isEmpty {
            let bob = DelightCatalog.selectBob(context: .celebration, cursor: &state.variantCursor)
            publish(context: .celebration, bob: bob)
        }
        burnHigh = currentMetrics.values.map(\.used).max() ?? 0 >= 70
        previousMetrics = currentMetrics
    }

    private func publish(context: MascotContext, bob: BobVariant? = nil, poke: PokeVariant? = nil) {
        requestID += 1
        animationRequest = AnimationRequest(context: context, bob: bob, poke: poke, id: requestID)
    }

    private func saveSoon() {
        persistence.save(state)
    }
}
