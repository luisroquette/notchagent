import Foundation

/// Codex CLI rollouts (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`) emit
/// `token_count` events carrying cumulative totals AND authoritative rate-limit
/// percentages for the 5h (primary) and weekly (secondary) windows.
struct CodexRateWindow: Sendable, Equatable {
    var usedPercent: Double
    var windowMinutes: Int?
    var resetsAt: Date?
}

struct CodexTokenInfo: Sendable {
    var timestamp: Date?
    /// Normalized: `input` excludes cached tokens, cached input goes to `cacheRead`.
    var totals: TokenUsage
    var primary: CodexRateWindow?
    var secondary: CodexRateWindow?
    var planType: String?
    var limitName: String?
    /// Model driving this rollout (from the newest `turn_context` event).
    var model: String?

    /// Codex changes window semantics per plan (some plans report a single
    /// weekly window as `primary`, `secondary: null`). Classify by duration
    /// instead of position.
    var sessionWindow: CodexRateWindow? {
        [primary, secondary].compactMap(\.self).first { ($0.windowMinutes ?? 0) <= 24 * 60 }
    }

    var weeklyWindow: CodexRateWindow? {
        [primary, secondary].compactMap(\.self).first { ($0.windowMinutes ?? 0) > 24 * 60 }
    }
}

enum CodexRolloutParser {
    private struct Event: Decodable {
        struct Payload: Decodable {
            struct Info: Decodable {
                struct Totals: Decodable {
                    let inputTokens: Int?
                    let cachedInputTokens: Int?
                    let outputTokens: Int?
                    let totalTokens: Int?
                }
                let totalTokenUsage: Totals?
            }
            struct RateLimits: Decodable {
                struct Window: Decodable {
                    let usedPercent: Double?
                    let windowMinutes: Int?
                    let resetsAt: Double?
                }
                let primary: Window?
                let secondary: Window?
                let planType: String?
                let limitName: String?
            }
            let type: String?
            let info: Info?
            let rateLimits: RateLimits?
        }
        let timestamp: String?
        let type: String?
        let payload: Payload?
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private struct TurnContextEvent: Decodable {
        struct Payload: Decodable {
            let model: String?
        }
        let type: String?
        let payload: Payload?
    }

    /// Scans the file tail backwards for the newest `token_count` event and
    /// the newest `turn_context` (which names the model). Tail-only keeps
    /// refreshes cheap even on very long rollouts.
    static func latestTokenInfo(at url: URL, tailBytes: Int = 2 * 1024 * 1024) throws -> CodexTokenInfo? {
        let lines = try JSONLReader.tailLines(at: url, maxBytes: tailBytes)
        var info: CodexTokenInfo?
        var model: String?

        for data in lines.reversed() {
            if info == nil,
               let event = try? decoder.decode(Event.self, from: data),
               event.payload?.type == "token_count" {
                let payload = event.payload
                let totals = payload?.info?.totalTokenUsage
                let cached = totals?.cachedInputTokens ?? 0
                let input = totals?.inputTokens ?? 0
                info = CodexTokenInfo(
                    timestamp: event.timestamp.flatMap(Timestamps.parseISO8601),
                    totals: TokenUsage(
                        input: max(0, input - cached),
                        output: totals?.outputTokens ?? 0,
                        cacheWrite: 0,
                        cacheRead: cached
                    ),
                    primary: window(from: payload?.rateLimits?.primary),
                    secondary: window(from: payload?.rateLimits?.secondary),
                    planType: payload?.rateLimits?.planType,
                    limitName: payload?.rateLimits?.limitName
                )
            }
            if model == nil,
               let event = try? decoder.decode(TurnContextEvent.self, from: data),
               event.type == "turn_context",
               let contextModel = event.payload?.model {
                model = contextModel
            }
            if info != nil, model != nil {
                break
            }
        }
        info?.model = model
        return info
    }

    private static func window(from raw: Event.Payload.RateLimits.Window?) -> CodexRateWindow? {
        guard let raw, let used = raw.usedPercent else { return nil }
        return CodexRateWindow(
            usedPercent: used,
            windowMinutes: raw.windowMinutes,
            resetsAt: raw.resetsAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}
