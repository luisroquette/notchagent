import Foundation

/// One micro-reaction of the mascot. `.ignored` means the mascot DECIDED
/// not to react (agency); `.none` means no signal was offered.
public enum MascotGesture: String, Codable, CaseIterable, Sendable {
    case none, ignored, blink, lookAtCursor, tilt, hop, stretch, yawn, nod
}

public enum MascotMood: String, Codable, CaseIterable, Sendable {
    case curious, calm, sleepy, alert
}

public enum DelightMoment: String, Codable, CaseIterable, Sendable {
    case quotaReset, peakPassed, midnight, firstExpandOfDay, idleThirtySeconds, randomExpand
}

/// The mascot's persistent inner life. Everything the engine needs to feel
/// continuous across launches.
public struct MascotMindState: Codable, Equatable, Sendable {
    public var mood: MascotMood
    public var energy: Double
    public var affection: Double
    public var lastSeen: Date?
    public var lastExpandedDay: String?
    public var lastGesture: MascotGesture?
    public var ignoresInARow: Int
    public var gestureCooldownUntil: Date?

    public init(
        mood: MascotMood = .calm,
        energy: Double = 0.8,
        affection: Double = 0.5,
        lastSeen: Date? = nil,
        lastExpandedDay: String? = nil,
        lastGesture: MascotGesture? = nil,
        ignoresInARow: Int = 0,
        gestureCooldownUntil: Date? = nil
    ) {
        self.mood = mood
        self.energy = energy
        self.affection = affection
        self.lastSeen = lastSeen
        self.lastExpandedDay = lastExpandedDay
        self.lastGesture = lastGesture
        self.ignoresInARow = ignoresInARow
        self.gestureCooldownUntil = gestureCooldownUntil
    }
}

/// Deterministic RNG for tests; production uses SystemRandomNumberGenerator.
public struct SplitMix64: RandomNumberGenerator {
    public var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Pure engine: no timers, no actors. Deterministic for a given RNG.
public enum MascotMindCore {
    /// Energy decays slowly with idle time: ~0.18/h.
    static let energyDecayPerSecond = 0.00005

    public static func recomputeMood(energy: Double, affection: Double, burnHigh: Bool) -> MascotMood {
        if burnHigh { return .alert }
        if energy < 0.3 { return .sleepy }
        if energy > 0.7 && affection > 0.6 { return .curious }
        return .calm
    }

    public static func evolveTick(state: inout MascotMindState, now: Date, idleSeconds: Double, burnHigh: Bool) {
        state.energy = min(1, max(0, state.energy - idleSeconds * energyDecayPerSecond))
        state.mood = recomputeMood(energy: state.energy, affection: state.affection, burnHigh: burnHigh)
        state.lastSeen = now
    }

    /// Events push; the mascot decides. Never reacts within the cooldown.
    /// Chance to ignore shrinks with affection and with event importance;
    /// two consecutive ignores force the third (teimosia).
    public static func nudge(
        state: inout MascotMindState,
        moment: DelightMoment,
        now: Date,
        rng: inout some RandomNumberGenerator
    ) -> MascotGesture {
        if let until = state.gestureCooldownUntil, until > now {
            return .none
        }
        let weight = DelightCatalog.weight(for: moment)
        let ignoreChance = max(0.05, 0.35 - 0.25 * state.affection) * (1.0 - weight * 0.5)
        if state.ignoresInARow < 2, Double.random(in: 0..<1, using: &rng) < ignoreChance {
            state.ignoresInARow += 1
            return .ignored
        }
        let gesture = chooseGesture(state: state, moment: moment, rng: &rng)
        state.ignoresInARow = 0
        state.lastGesture = gesture
        state.gestureCooldownUntil = now.addingTimeInterval(DelightCatalog.reactionCooldown)
        return gesture
    }

    /// Weighted roulette over the catalog gestures for the moment, filtered
    /// by mood affinity and never the same gesture twice in a row. The
    /// catalog is the invariant: if the mood has no affinity for any
    /// eligible gesture, the whole catalog is weighted equally instead —
    /// the reaction ALWAYS belongs to its moment.
    public static func chooseGesture(
        state: MascotMindState,
        moment: DelightMoment,
        rng: inout some RandomNumberGenerator
    ) -> MascotGesture {
        let affinity = gestureAffinity(state.mood)
        let catalog = DelightCatalog.gestures(for: moment)
        let eligible = catalog.filter { $0 != state.lastGesture }
        guard !eligible.isEmpty else { return catalog.first ?? .blink }
        let moodAligned = eligible.filter { affinity[$0] != nil }
        let pool = moodAligned.isEmpty ? eligible : moodAligned
        let total = pool.reduce(0.0) { $0 + (affinity[$1] ?? 0.5) }
        var roll = Double.random(in: 0..<total, using: &rng)
        for gesture in pool {
            roll -= affinity[gesture] ?? 0.5
            if roll <= 0 { return gesture }
        }
        return pool.last ?? catalog.first ?? .blink
    }

    /// Unprompted gesture: the mascot acts on its own, more when energetic.
    public static func selfInitiatedGesture(
        state: inout MascotMindState,
        now: Date,
        rng: inout some RandomNumberGenerator
    ) -> MascotGesture {
        if let until = state.gestureCooldownUntil, until > now {
            return .none
        }
        guard Double.random(in: 0..<1, using: &rng) < 0.15 * state.energy else {
            return .none
        }
        let gesture = chooseGesture(state: state, moment: .randomExpand, rng: &rng)
        state.lastGesture = gesture
        state.gestureCooldownUntil = now.addingTimeInterval(DelightCatalog.reactionCooldown)
        return gesture
    }

    public static func firstExpandOfDay(state: MascotMindState, dayKey: String) -> Bool {
        state.lastExpandedDay != dayKey
    }

    private static func gestureAffinity(_ mood: MascotMood) -> [MascotGesture: Double] {
        switch mood {
        case .alert: [.blink: 0.5, .nod: 0.5]
        case .sleepy: [.yawn: 0.6, .blink: 0.4]
        case .curious: [.lookAtCursor: 0.3, .tilt: 0.3, .hop: 0.2, .stretch: 0.2]
        case .calm: [.blink: 0.4, .tilt: 0.3, .stretch: 0.3]
        }
    }
}
