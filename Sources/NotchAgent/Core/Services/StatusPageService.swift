import Foundation

/// Unresolved-incident line from status.claude.com (same feed the
/// claude-usage-stick shows on its Models screen). Cached for 10 minutes;
/// failures keep the last known value.
actor StatusPageService {
    private var lastFetch = Date.distantPast
    private var incident: String?
    private let ttl: TimeInterval = 600

    private struct Payload: Decodable {
        struct Incident: Decodable {
            let name: String
        }
        let incidents: [Incident]
    }

    func activeIncident() async -> String? {
        if Date().timeIntervalSince(lastFetch) < ttl {
            return incident
        }
        lastFetch = Date()
        guard let url = URL(string: "https://status.claude.com/api/v2/incidents/unresolved.json") else {
            return incident
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: request)
            incident = try JSONDecoder().decode(Payload.self, from: data).incidents.first?.name
        } catch {
            Log.refresh.info("status page fetch failed: \(error.localizedDescription, privacy: .public)")
        }
        return incident
    }
}
