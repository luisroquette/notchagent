import Foundation

/// Hourly history per provider, kept for 30 days in a single JSON file.
/// Each point stores the session-window totals observed at that hour (last
/// write wins within the hour) — enough for sparklines and dashboard charts
/// without a database.
actor HistoryStore {
    struct Point: Codable, Sendable, Equatable {
        var hour: Date
        var provider: ProviderID
        var sessionTokens: Int
        var weeklyTokens: Int
        var costUSD: Double
        var sessionPercent: Double?
    }

    private let fileURL: URL
    private var points: [Point] = []
    private var loaded = false
    private static let retention: TimeInterval = 30 * 24 * 3600

    init(fileURL: URL = AppPaths.appSupport.appendingPathComponent("history.json")) {
        self.fileURL = fileURL
    }

    func record(_ snapshot: UsageSnapshot) {
        loadIfNeeded()
        let hour = snapshot.capturedAt.flooredToHour
        let point = Point(
            hour: hour,
            provider: snapshot.provider,
            sessionTokens: snapshot.session?.tokens.total ?? 0,
            weeklyTokens: snapshot.weekly?.tokens.total ?? 0,
            costUSD: snapshot.weekly?.cost?.amountUSD ?? 0,
            sessionPercent: snapshot.session?.usedPercent
        )
        if let index = points.lastIndex(where: { $0.hour == hour && $0.provider == snapshot.provider }) {
            points[index] = point
        } else {
            points.append(point)
        }
        prune()
        persist()
    }

    func series(for provider: ProviderID, lastHours: Int) -> [Point] {
        loadIfNeeded()
        let cutoff = Date().addingTimeInterval(-Double(lastHours) * 3600)
        return points
            .filter { $0.provider == provider && $0.hour >= cutoff }
            .sorted { $0.hour < $1.hour }
    }

    func allPoints(lastHours: Int) -> [Point] {
        loadIfNeeded()
        let cutoff = Date().addingTimeInterval(-Double(lastHours) * 3600)
        return points.filter { $0.hour >= cutoff }.sorted { $0.hour < $1.hour }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        points = (try? decoder.decode([Point].self, from: data)) ?? []
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.retention)
        points.removeAll { $0.hour < cutoff }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(points)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.persistence.error("history save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
