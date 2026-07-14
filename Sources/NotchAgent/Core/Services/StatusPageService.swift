import Foundation

/// Unresolved-incident line from status.claude.com (same feed the
/// claude-usage-stick shows on its Models screen). Cached for 10 minutes;
/// failures keep the last known value.
actor StatusPageService {
    private var lastFetch = Date.distantPast
    private var lastSuccess = Date.distantPast
    private var incident: String?
    private let ttl: TimeInterval = 600
    /// Offline for longer than this → stop showing a possibly-resolved incident.
    private let staleAfter: TimeInterval = 30 * 60

    private struct Payload: Decodable {
        struct Incident: Decodable {
            let name: String
        }
        let incidents: [Incident]
    }

    func activeIncident() async -> String? {
        if Date().timeIntervalSince(lastFetch) >= ttl {
            lastFetch = Date()
            if let url = URL(string: "https://status.claude.com/api/v2/incidents/unresolved.json") {
                do {
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 10
                    let (data, _) = try await URLSession.shared.data(for: request)
                    incident = try JSONDecoder().decode(Payload.self, from: data).incidents.first?.name
                    lastSuccess = Date()
                } catch {
                    Log.refresh.info("status page fetch failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        // An incident is only as true as our last successful fetch.
        return Date().timeIntervalSince(lastSuccess) < staleAfter ? incident : nil
    }
}
