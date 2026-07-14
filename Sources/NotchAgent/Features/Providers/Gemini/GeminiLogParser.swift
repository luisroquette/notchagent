import Foundation

/// Gemini CLI keeps prompt logs at `~/.gemini/tmp/<project-hash>/logs.json` —
/// an array of `{sessionId, messageId, type, message, timestamp}` entries.
/// Token usage is NOT written to disk by the CLI, so this provider reports
/// activity (prompts/sessions) and declares tokens unavailable.
struct GeminiLogStat: Sendable {
    var promptTimestamps: [Date] = []
    var sessionIDs: Set<String> = []
    var lastActivity: Date?
}

enum GeminiLogParser {
    private struct Entry: Decodable {
        let sessionId: String?
        let type: String?
        let timestamp: String?
    }

    static func parseLogFile(at url: URL) throws -> GeminiLogStat {
        let data = try Data(contentsOf: url)
        let entries = try JSONDecoder().decode([Entry].self, from: data)

        var stat = GeminiLogStat()
        for entry in entries where entry.type == "user" {
            guard let ts = entry.timestamp.flatMap(Timestamps.parseISO8601) else { continue }
            stat.promptTimestamps.append(ts)
            if let session = entry.sessionId {
                stat.sessionIDs.insert(session)
            }
            if stat.lastActivity.map({ ts > $0 }) ?? true {
                stat.lastActivity = ts
            }
        }
        return stat
    }
}
