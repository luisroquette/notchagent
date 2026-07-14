import Foundation

public struct PercentSample: Sendable, Equatable {
    public var date: Date
    public var percent: Double

    public init(date: Date, percent: Double) {
        self.date = date
        self.percent = percent
    }
}

/// Projects session-quota exhaustion from recent percent samples, mirroring
/// the claude-usage-stick "runs out at 16:40" verdict. Pure functions, fully
/// unit-tested.
public enum BurnRate {
    public struct Projection: Sendable, Equatable {
        public var percentPerHour: Double
        /// nil = will not run out before the window resets.
        public var exhaustsAt: Date?
    }

    /// - Parameters:
    ///   - samples: chronological (date, percent) observations for one provider.
    ///   - resetsAt: end of the current window; projections beyond it are moot.
    ///   - lookback: only samples this recent contribute to the rate.
    public static func project(
        samples: [PercentSample],
        resetsAt: Date?,
        now: Date = Date(),
        lookback: TimeInterval = 90 * 60
    ) -> Projection? {
        var recent = samples.filter { now.timeIntervalSince($0.date) <= lookback }
        // A window reset shows up as a percent drop — keep only the monotone tail.
        if recent.count > 1 {
            for index in stride(from: recent.count - 1, through: 1, by: -1)
            where recent[index - 1].percent > recent[index].percent + 5 {
                recent = Array(recent.suffix(from: index))
                break
            }
        }
        guard let first = recent.first, let last = recent.last,
              last.date > first.date
        else { return nil }

        let hours = last.date.timeIntervalSince(first.date) / 3600
        guard hours >= 0.05 else { return nil }

        let rate = (last.percent - first.percent) / hours
        guard rate > 0.1 else {
            return Projection(percentPerHour: max(rate, 0), exhaustsAt: nil)
        }

        let hoursLeft = (100 - last.percent) / rate
        let exhaustsAt = last.date.addingTimeInterval(hoursLeft * 3600)
        if let resetsAt, exhaustsAt >= resetsAt {
            return Projection(percentPerHour: rate, exhaustsAt: nil)
        }
        return Projection(percentPerHour: rate, exhaustsAt: exhaustsAt)
    }

    /// Plain-language verdict for the UI. nil when there is nothing to say.
    public static func verdict(_ projection: Projection?, now: Date = Date()) -> String? {
        guard let projection, projection.percentPerHour > 0.1 else { return nil }
        let rate = String(format: "+%.0f%%/h", projection.percentPerHour)
        if let exhaustsAt = projection.exhaustsAt {
            return "\(rate) · runs out \(Format.time(exhaustsAt)) (in \(Format.countdown(to: exhaustsAt, from: now)))"
        }
        return "\(rate) · safe until reset"
    }
}
