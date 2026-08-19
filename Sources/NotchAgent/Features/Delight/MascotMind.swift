import AppKit
import Foundation
import Observation

/// The mascot's running mind: owns the persisted state, ticks every 60s,
/// receives nudges from app events and turns them into gestures — which it
/// may ignore. Everything here is gated by `settings.delightEnabled`.
@MainActor
@Observable
public final class MascotMind {
    public private(set) var state: MascotMindState
    /// The gesture the puppet is currently performing (`.none` when idle).
    public private(set) var activeGesture: MascotGesture = .none

    private var rng = SystemRandomNumberGenerator()
    private let persistence: MascotMindPersistence
    private let settings: PreferencesStore
    private weak var store: UsageStore?
    private var tickTask: Task<Void, Never>?
    private var lastTickAt = Date()
    private var lastInteractionAt = Date()
    private var isPanelOpen = false
    private var burnHigh = false
    private var previousMetrics: [ProviderID: GaugeMetric] = [:]
    private let sounds = DelightSounds()

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

    /// Called when the panel expands. First expand of the day bumps
    /// affection; other expands roll a ~20% random gesture. Expand-triggered
    /// reactions are scheduled AFTER the panel transition — a blink during
    /// the 0.38s expand animation is invisible, the panel's motion swallows it.
    public func noteExpanded(now: Date = Date()) {
        lastInteractionAt = now
        isPanelOpen = true
        guard settings.settings.delightEnabled else { return }
        if MascotMindCore.firstExpandOfDay(state: state, dayKey: DelightSignals.dayKey(now)) {
            state.lastExpandedDay = DelightSignals.dayKey(now)
            state.affection = min(1, state.affection + DelightCatalog.affectionBump(firstExpandOfDay: true))
            scheduleReaction(to: .firstExpandOfDay)
        } else if Double.random(in: 0..<1, using: &rng) < 0.2 {
            scheduleReaction(to: .randomExpand)
        }
        saveSoon()
    }

    /// Delays a reaction until the panel has settled on screen.
    private func scheduleReaction(to moment: DelightMoment) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.react(to: moment, now: Date())
        }
    }

    /// Called when the panel collapses — the mascot never performs (or
    /// makes noise) with the panel closed.
    public func noteCollapsed(now: Date = Date()) {
        lastInteractionAt = now
        isPanelOpen = false
        activeGesture = .none
    }

    /// The usage peak passed (alert cleared).
    public func notePeakPassed(now: Date = Date()) {
        guard settings.settings.delightEnabled else { return }
        react(to: .peakPassed, now: now)
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
            react(to: .midnight, now: now)
        }
        if idle >= 30 {
            react(to: .idleThirtySeconds, now: now)
        } else {
            let gesture = MascotMindCore.selfInitiatedGesture(state: &state, now: now, rng: &rng)
            if gesture != .none { perform(gesture) }
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
            react(to: .quotaReset, now: now)
        }
        burnHigh = currentMetrics.values.map(\.used).max() ?? 0 >= 70
        previousMetrics = currentMetrics
    }

    private func react(to moment: DelightMoment, now: Date) {
        var s = state
        let gesture = MascotMindCore.nudge(state: &s, moment: moment, now: now, rng: &rng)
        state = s
        if gesture != .none, gesture != .ignored {
            perform(gesture)
        }
        saveSoon()
    }

    private func perform(_ gesture: MascotGesture) {
        guard isPanelOpen else { return }
        activeGesture = gesture
        let eligible = DelightSounds.eligibility(
            enabled: true,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            screenReader: NSWorkspace.shared.isVoiceOverEnabled
        )
        if eligible {
            sounds.play(gesture)
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.activeGesture = .none
        }
    }

    private func saveSoon() {
        persistence.save(state)
    }
}
