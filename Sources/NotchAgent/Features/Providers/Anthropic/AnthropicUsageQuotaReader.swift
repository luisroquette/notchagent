import Foundation

#if os(macOS)
import WebKit

/// Reads Claude subscription quota from the authenticated Usage page. This is
/// the zero-cost fallback for the 1-token API probe and reuses the isolated
/// Claude web session already connected in Settings.
@MainActor
final class AnthropicUsageQuotaReader: NSObject, WKNavigationDelegate {
    private static let usageURL = URL(string: "https://claude.ai/settings/usage")!
    private let accountID: UUID
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<ClaudeQuota?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    init(accountID: UUID) {
        self.accountID = accountID
    }

    func fetchQuota() async -> ClaudeQuota? {
        finish(nil)
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1200, height: 900),
            configuration: APIAccountPortalSession.configuration(for: accountID)
        )
        view.navigationDelegate = self
        webView = view
        view.load(URLRequest(url: Self.usageURL))
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.finish(nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        poll(attempt: 0)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(nil)
    }

    private func poll(attempt: Int) {
        guard let webView, continuation != nil else { return }
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] value, _ in
            guard let self else { return }
            if let text = value as? String,
               let quota = Self.parseUsageText(text, now: Date()) {
                Log.providers.info("claude usage portal parsed chars=\(text.count, privacy: .public)")
                self.finish(quota)
                return
            }
            guard attempt < 10 else {
                self.finish(nil)
                return
            }
            self.pollTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.poll(attempt: attempt + 1)
            }
        }
    }

    private func finish(_ quota: ClaudeQuota?) {
        timeoutTask?.cancel()
        pollTask?.cancel()
        timeoutTask = nil
        pollTask = nil
        continuation?.resume(returning: quota)
        continuation = nil
        webView = nil
    }

    nonisolated static func parseUsageText(_ text: String, now: Date = Date()) -> ClaudeQuota? {
        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
        let sessionUsedMarker = firstMatch(
            pattern: #"(?is)(?:sessão\s+atual|current\s+session).{0,350}?([0-9]+(?:[.,][0-9]+)?)\s*%\s*(?:usado|used)"#,
            in: normalized
        )
        let weeklyUsedMarker = firstMatch(
            pattern: #"(?is)(?:todos\s+os\s+modelos|all\s+models).{0,350}?([0-9]+(?:[.,][0-9]+)?)\s*%\s*(?:usado|used)"#,
            in: normalized
        )
        let sessionRemainingMarker = firstMatch(
            pattern: #"(?is)([0-9]+(?:[.,][0-9]+)?)\s*%\s*(?:of\s+)?(?:5h|5[\s-]*hour|sessão\s+de\s+5h)[^\n]{0,90}(?:left|remaining|restante)"#,
            in: normalized
        )
        let weeklyRemainingMarker = firstMatch(
            pattern: #"(?is)([0-9]+(?:[.,][0-9]+)?)\s*%\s*(?:of\s+)?(?:weekly\s+limit|weekly|limite\s+semanal)[^\n]{0,90}(?:left|remaining|restante)"#,
            in: normalized
        )
        guard sessionUsedMarker != nil || weeklyUsedMarker != nil
                || sessionRemainingMarker != nil || weeklyRemainingMarker != nil
        else { return nil }

        let sessionUsed = sessionUsedMarker.flatMap { decimalPercent($0.value) }
            ?? sessionRemainingMarker.flatMap { decimalPercent($0.value).map { 100 - $0 } }
        let weeklyUsed = weeklyUsedMarker.flatMap { decimalPercent($0.value) }
            ?? weeklyRemainingMarker.flatMap { decimalPercent($0.value).map { 100 - $0 } }
        let sessionScope = sessionUsedMarker.map { String(normalized[$0.range]) }
            ?? sessionRemainingMarker.map { forwardText(from: $0.range, in: normalized, radius: 260) }
        let weeklyScope = weeklyUsedMarker.map { String(normalized[$0.range]) }
            ?? weeklyRemainingMarker.map { forwardText(from: $0.range, in: normalized, radius: 260) }
        let sessionReset = sessionScope.flatMap { resetDate(in: $0, now: now) }
        let weeklyReset = weeklyScope.flatMap { resetDate(in: $0, now: now) }

        let highestUse = [sessionUsed, weeklyUsed].compactMap { $0 }.max()
        let remaining = highestUse.map { 100 - $0 }
        let status: QuotaStatus? = remaining.map {
            if $0 <= 0 { return .blocked }
            if $0 <= 20 { return .warning }
            return .ok
        }
        let limitingWindow: String?
        if let sessionUsed, let weeklyUsed {
            limitingWindow = sessionUsed >= weeklyUsed ? "five_hour" : "seven_day"
        } else if sessionUsed != nil {
            limitingWindow = "five_hour"
        } else {
            limitingWindow = "seven_day"
        }

        return ClaudeQuota(
            sessionPercent: sessionUsed,
            weeklyPercent: weeklyUsed,
            sessionResetsAt: sessionReset,
            weeklyResetsAt: weeklyReset,
            status: status,
            limitingWindow: limitingWindow,
            fetchedAt: now
        )
    }

    private struct Match {
        let value: String
        let range: Range<String.Index>
    }

    nonisolated private static func firstMatch(pattern: String, in text: String) -> Match? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text),
              let fullRange = Range(match.range(at: 0), in: text)
        else { return nil }
        return Match(value: String(text[valueRange]), range: fullRange)
    }

    nonisolated private static func decimalPercent(_ raw: String) -> Double? {
        Double(raw.replacingOccurrences(of: ",", with: ".")).map { min(max($0, 0), 100) }
    }

    nonisolated private static func forwardText(
        from range: Range<String.Index>,
        in text: String,
        radius: Int
    ) -> String {
        let upper = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[range.lowerBound..<upper])
    }

    nonisolated private static func resetDate(in text: String, now: Date) -> Date? {
        let unit = #"(?:dias?|days?|d|horas?|hours?|h|minutos?|minutes?|mins?|min|m)"#
        let durationPattern = #"(?:(?:[0-9]+)\s*"# + unit + #"\s*){1,3}"#
        let patterns = [
            #"(?is)(?:resets?|reinicia|redefine)(?:\s+(?:em|in))?\s*("# + durationPattern + #")"#,
            #"(?is)(?:resets?|reinicia|redefine)[^\n]*\n\s*("# + durationPattern + #")"#,
        ]
        guard let duration = patterns.lazy.compactMap({ captured($0, in: text) }).first else {
            return nil
        }
        let days = component(#"(?:dias?|days?|d)"#, in: duration)
        let hours = component(#"(?:horas?|hours?|h)"#, in: duration)
        let minutes = component(#"(?:minutos?|minutes?|mins?|min|m)"#, in: duration)
        let seconds = TimeInterval(days * 86_400 + hours * 3_600 + minutes * 60)
        return seconds > 0 ? now.addingTimeInterval(seconds) : nil
    }

    nonisolated private static func captured(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    nonisolated private static func component(_ unitPattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)([0-9]+)\s*"# + unitPattern
        ),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return 0 }
        return Int(text[range]) ?? 0
    }
}
#endif
