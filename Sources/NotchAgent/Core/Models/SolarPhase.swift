import Foundation

/// The four sky regimes the procedural gradient interpolates between.
public enum DayPhase: Equatable, Sendable {
    case night
    case dawn
    case day
    case dusk
}

/// Where the local sun sits in its daily arc, derived from today's
/// sunrise/sunset (Open-Meteo daily block, local timezone). Dawn and dusk
/// get a 60-minute transition window (±30 min around the moment) — inside
/// it, `transition` runs 0→1 and the palette interpolates.
public struct SolarPhase: Equatable, Sendable {
    public let phase: DayPhase
    /// 0...1 inside dawn/dusk; 0 elsewhere.
    public let transition: Double

    public init(phase: DayPhase, transition: Double) {
        self.phase = phase
        self.transition = min(1, max(0, transition))
    }

    public static let transitionWindow: TimeInterval = 30 * 60

    /// Falls back to the snapshot's isDay flag when sunrise/sunset are
    /// missing (e.g. legacy cached snapshots) — never nil, never guesses a
    /// sunset that isn't there.
    public static func at(now: Date, sunrise: Date?, sunset: Date?, isDay: Bool) -> SolarPhase {
        guard let sunrise, let sunset else {
            return SolarPhase(phase: isDay ? .day : .night, transition: 0)
        }

        if now < sunrise.addingTimeInterval(-transitionWindow) {
            return SolarPhase(phase: .night, transition: 0)
        }
        if now < sunrise.addingTimeInterval(transitionWindow) {
            let progress = now.timeIntervalSince(sunrise.addingTimeInterval(-transitionWindow))
                / (2 * transitionWindow)
            return SolarPhase(phase: .dawn, transition: progress)
        }
        if now < sunset.addingTimeInterval(-transitionWindow) {
            return SolarPhase(phase: .day, transition: 0)
        }
        if now < sunset.addingTimeInterval(transitionWindow) {
            let progress = now.timeIntervalSince(sunset.addingTimeInterval(-transitionWindow))
                / (2 * transitionWindow)
            return SolarPhase(phase: .dusk, transition: progress)
        }
        return SolarPhase(phase: .night, transition: 0)
    }
}
