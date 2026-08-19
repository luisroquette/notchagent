import Foundation

/// The fan of moments and their weights — "sem anúncio": low weights mean
/// the mascot often just carries on.
public enum DelightCatalog {
    /// One reaction per 90s at most.
    public static let reactionCooldown: TimeInterval = 90

    public static func weight(for moment: DelightMoment) -> Double {
        switch moment {
        case .quotaReset: 0.9
        case .firstExpandOfDay: 0.8
        case .peakPassed: 0.7
        case .midnight: 0.6
        case .idleThirtySeconds: 0.4
        case .randomExpand: 0.3
        }
    }

    public static func gestures(for moment: DelightMoment) -> [MascotGesture] {
        switch moment {
        case .quotaReset: [.nod, .hop]
        case .firstExpandOfDay: [.lookAtCursor, .tilt]
        case .peakPassed: [.stretch, .blink]
        case .midnight: [.yawn, .blink]
        case .idleThirtySeconds: [.lookAtCursor, .blink]
        case .randomExpand: [.blink, .hop, .tilt, .stretch]
        }
    }

    // MARK: Contextual animation catalog

    /// Which bob variants belong to each context — the mascot's vocabulary
    /// per situation. Variety comes from contexts interleaving; the SAME
    /// context rotates through its set via round-robin, never repeating
    /// consecutively.
    public static func bobVariants(for context: MascotContext) -> [BobVariant] {
        switch context {
        case .greeting: [.swingUpDown, .swayPendulum, .bow]
        case .calm: [.swingUpDown, .swayPendulum, .hopBob, .doubleTake]
        case .tense: [.swayPendulum, .wobbleFall, .shiver]
        case .drowsy: [.swingUpDown]
        case .playful: [.hopBob, .wobbleFall, .doubleTake]
        case .relief: [.swayPendulum, .swingUpDown, .bow]
        case .celebration: [.hopBob, .swingUpDown]
        case .midnightMoment: [.swingUpDown, .yawnStretch]
        case .poke: []
        }
    }

    /// Round-robin over a context's bob set: deterministic variety — each
    /// selection advances the cursor so the next one differs.
    public static func selectBob(context: MascotContext, cursor: inout Int) -> BobVariant {
        let options = bobVariants(for: context)
        guard !options.isEmpty else { return .swingUpDown }
        let index = cursor % options.count
        cursor += 1
        return options[index]
    }

    /// Round-robin over the poke reactions (all three, never the same
    /// twice in a row).
    public static func selectPoke(cursor: inout Int) -> PokeVariant {
        let options = PokeVariant.allCases
        let index = cursor % options.count
        cursor += 1
        return options[index]
    }

    /// The travel personality per context: tense snaps, drowsy drags,
    /// playful overshoots.
    public static func easing(for context: MascotContext) -> EasingProfile {
        switch context {
        case .tense, .poke: .sharp
        case .drowsy, .midnightMoment: .sluggish
        case .playful, .celebration: .elastic
        default: .standard
        }
    }

    /// Which contexts wind up before committing — tense and drowsy have
    /// no energy for a wind-up; the rest preload with intent.
    public static func anticipation(for context: MascotContext) -> Bool {
        switch context {
        case .greeting, .calm, .playful, .celebration, .relief: true
        case .tense, .drowsy, .midnightMoment, .poke: false
        }
    }

    /// Which contexts drain with a tail — tense ends dead (a snap with a
    /// tail is a wobble); everything else drains.
    public static func followThrough(for context: MascotContext) -> Bool {
        context != .tense
    }

    /// Mood → context for an ordinary expand (greeting wins when it's the
    /// first expand of the day).
    public static func expandContext(mood: MascotMood, firstExpandOfDay: Bool) -> MascotContext {
        if firstExpandOfDay { return .greeting }
        switch mood {
        case .alert: return .tense
        case .sleepy: return .drowsy
        case .curious: return .playful
        case .calm: return .calm
        }
    }

    public static func affectionBump(firstExpandOfDay: Bool) -> Double {
        firstExpandOfDay ? 0.02 : 0
    }

    /// Being ignored for days cools the mascot off — capped so it never
    /// becomes unreachable.
    public static func affectionAbsencePenalty(absentDays: Int) -> Double {
        Double(min(max(absentDays, 0), 5)) * 0.01
    }
}
