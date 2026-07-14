import Foundation
import Security

/// Authoritative Claude quota read from Anthropic API response headers
/// (`anthropic-ratelimit-unified-*`), the same technique used by
/// claude-usage-stick: a `max_tokens: 1` request whose body is discarded —
/// only the rate-limit headers matter. Quota impact is negligible (1 token).
struct ClaudeQuota: Sendable, Equatable {
    var sessionPercent: Double?
    var weeklyPercent: Double?
    var sessionResetsAt: Date?
    var weeklyResetsAt: Date?
    var status: QuotaStatus?
    /// Which window is currently the limiting factor ("five_hour"/"seven_day").
    var limitingWindow: String?
    var fetchedAt: Date
}

/// Locates the Claude Code OAuth token without ever logging or persisting it.
/// Order: env var → ~/.claude/.credentials.json → macOS Keychain (the read
/// triggers a one-time user consent dialog, which is expected and documented).
enum ClaudeTokenLocator {
    static func oauthToken() -> String? {
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
           !env.isEmpty {
            return env
        }
        let file = AppPaths.home.appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: file), let token = parseCredentials(data) {
            return token
        }
        return keychainToken()
    }

    /// Parses Claude Code's credentials JSON; rejects clearly expired tokens.
    static func parseCredentials(_ data: Data, now: Date = Date()) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        if let expiresAt = oauth["expiresAt"] as? Double,
           Date(timeIntervalSince1970: expiresAt / 1000) < now {
            return nil
        }
        return token
    }

    private static func keychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                Log.providers.info("claude probe: keychain unavailable (status \(status, privacy: .public))")
            }
            return nil
        }
        if let token = parseCredentials(data) {
            return token
        }
        // Some setups store the bare token instead of the JSON blob.
        if let raw = String(data: data, encoding: .utf8), raw.hasPrefix("sk-ant-") {
            return raw
        }
        return nil
    }
}

actor ClaudeQuotaProbe {
    /// Probe rotation doubles as a per-model health check (stick-style):
    /// each cycle pings the next model, so every model is verified every
    /// N cycles at ~1 token each.
    static let modelRotation: [String] = [
        "claude-haiku-4-5-20251001",
        "claude-sonnet-5",
        "claude-opus-4-8",
        "claude-fable-5",
    ]

    private var cache: ClaudeQuota?
    private var lastAttempt = Date.distantPast
    private var missingTokenLogged = false
    private var rotationIndex = 0
    private var health: [String: ModelHealth] = [:]
    private let minInterval: TimeInterval

    init(minInterval: TimeInterval = 60) {
        self.minInterval = minInterval
    }

    /// Latest per-model probe results, in rotation order.
    func modelHealthSnapshot() -> [ModelHealth] {
        Self.modelRotation.compactMap { health[$0] }
    }

    /// Cached quota when fresh; otherwise probes the API. Returns the last
    /// good value on transient failures — never throws into the provider.
    func currentQuota() async -> ClaudeQuota? {
        if Date().timeIntervalSince(lastAttempt) < minInterval {
            return cache
        }
        guard let token = ClaudeTokenLocator.oauthToken() else {
            if !missingTokenLogged {
                missingTokenLogged = true
                Log.providers.info("claude probe: no OAuth token found — falling back to local budgets")
            }
            lastAttempt = Date()
            return cache
        }
        missingTokenLogged = false
        lastAttempt = Date()

        let model = Self.modelRotation[rotationIndex % Self.modelRotation.count]
        rotationIndex += 1

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-cli/2.1.207 (external, cli)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]],
        ])

        let startedAt = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return cache }
            recordHealth(model: model, statusCode: http.statusCode, startedAt: startedAt)

            // Rate-limit headers are present even on 429 (rejected).
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String {
                    headers[key.lowercased()] = value
                }
            }
            let quota = Self.parse(headers: headers)
            if quota.sessionPercent != nil || quota.weeklyPercent != nil {
                cache = quota
                Log.providers.debug("claude probe ok (\(model, privacy: .public), http \(http.statusCode, privacy: .public))")
            } else {
                Log.providers.error("claude probe: no rate-limit headers (http \(http.statusCode, privacy: .public))")
            }
            return cache
        } catch {
            health[model] = ModelHealth(model: model, status: .error, latencyMs: nil, checkedAt: Date())
            Log.providers.error("claude probe failed: \(error.localizedDescription, privacy: .public)")
            return cache
        }
    }

    private func recordHealth(model: String, statusCode: Int, startedAt: Date) {
        let latency = Int(Date().timeIntervalSince(startedAt) * 1000)
        let status: ModelProbeStatus = switch statusCode {
        case 200..<300: .ok
        case 429: .limited
        default: .error
        }
        health[model] = ModelHealth(
            model: model,
            status: status,
            latencyMs: status == .ok ? latency : nil,
            checkedAt: Date()
        )
    }

    /// Pure and testable. Keys must be lowercased.
    static func parse(headers: [String: String], now: Date = Date()) -> ClaudeQuota {
        ClaudeQuota(
            sessionPercent: percent(headers["anthropic-ratelimit-unified-5h-utilization"]),
            weeklyPercent: percent(headers["anthropic-ratelimit-unified-7d-utilization"]),
            sessionResetsAt: reset(headers["anthropic-ratelimit-unified-5h-reset"]),
            weeklyResetsAt: reset(headers["anthropic-ratelimit-unified-7d-reset"]),
            status: status(headers["anthropic-ratelimit-unified-status"]),
            limitingWindow: headers["anthropic-ratelimit-unified-representative-claim"],
            fetchedAt: now
        )
    }

    /// Utilization arrives on a 0–1 scale; tolerate a switch to 0–100.
    /// Only values ≤ 1.0 (mathematically valid utilizations) are treated as
    /// the 0–1 scale — anything above passes through as a percentage. If the
    /// scale is ambiguous we err toward UNDERSTATING (a quiet gauge) rather
    /// than a false 100% that would fire the whole alert cascade.
    private static func percent(_ raw: String?) -> Double? {
        guard let raw, let value = Double(raw) else { return nil }
        let scaled = value <= 1.0 ? value * 100 : value
        return min(max(scaled, 0), 100)
    }

    /// Reset headers are epoch seconds; tolerate ISO 8601 as well.
    private static func reset(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let epoch = Double(raw), epoch > 1_000_000_000 {
            return Date(timeIntervalSince1970: epoch)
        }
        return Timestamps.parseISO8601(raw)
    }

    private static func status(_ raw: String?) -> QuotaStatus? {
        switch raw {
        case "allowed": .ok
        case "allowed_warning": .warning
        case "rejected": .blocked
        default: nil
        }
    }
}
