import Foundation

#if os(macOS)
import WebKit

/// Reads the paying Google account's recurring AI/Gemini subscription from
/// Google Payments. It is independent from Google Cloud and Gemini API costs.
@MainActor
final class GoogleSubscriptionReader: NSObject, WKNavigationDelegate {
    private static let activityURL = URL(
        string: "https://payments.google.com/gp/w/u/0/home/activity"
    )!
    private let accountID: UUID
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<AccountQuota?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    init(accountID: UUID) {
        self.accountID = accountID
    }

    static func makeLoginView(accountID: UUID) -> WKWebView {
        let view = WKWebView(
            frame: .zero,
            configuration: APIAccountPortalSession.configuration(for: accountID)
        )
        view.load(URLRequest(url: activityURL))
        return view
    }

    func fetchQuota() async -> AccountQuota? {
        finish(nil)
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1200, height: 900),
            configuration: APIAccountPortalSession.configuration(for: accountID)
        )
        view.navigationDelegate = self
        webView = view
        view.load(URLRequest(url: Self.activityURL))
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(18))
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
        let script = """
        (() => {
          const texts = [document.body ? document.body.innerText : ''];
          document.querySelectorAll('iframe').forEach((frame) => {
            try {
              const body = frame.contentDocument && frame.contentDocument.body;
              if (body) texts.push(body.innerText || '');
            } catch (_) {}
          });
          return texts.join('\\n');
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            guard let self else { return }
            if let text = value as? String, let quota = Self.parseBillingText(text) {
                Log.providers.info("google subscription parsed chars=\(text.count, privacy: .public)")
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

    private func finish(_ quota: AccountQuota?) {
        timeoutTask?.cancel()
        pollTask?.cancel()
        timeoutTask = nil
        pollTask = nil
        continuation?.resume(returning: quota)
        continuation = nil
        webView = nil
    }

    nonisolated static func parseBillingText(_ text: String) -> AccountQuota? {
        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
        guard let plan = googleAIPlan(in: normalized) else { return nil }
        let scope = nearbyText(around: plan, in: normalized, radius: 700)
        let isAnnual = annualCadence(in: scope)
        let divisor = isAnnual ? 12.0 : 1.0

        let brl = capture(
            pattern: #"(?i)R\$\s*([0-9][0-9.\s]*(?:,[0-9]{1,2})?)"#,
            in: scope
        ).flatMap { decimalNumber($0, decimalSeparator: ",") }
        let usd = capture(
            pattern: #"(?i)(?:US\s*\$|USD\s*|\$)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#,
            in: scope
        ).flatMap { decimalNumber($0, decimalSeparator: ".") }
        guard brl != nil || usd != nil else { return nil }

        return AccountQuota(
            service: .googleSubscription,
            usedPercent: nil,
            resetsAt: nil,
            note: "Google: plano \(plan) · \(isAnnual ? "equivalente mensal" : "mensal")",
            monthlyPlanUSD: usd.map { $0 / divisor },
            monthlyPlanBRL: brl.map { Decimal($0 / divisor) },
            planName: plan
        )
    }

    nonisolated private static func googleAIPlan(in text: String) -> String? {
        let candidates = [
            "Google AI Ultra",
            "Google AI Pro",
            "Google AI Plus",
            "Google One AI Premium",
            "Google One Premium AI",
            "Gemini Advanced",
        ]
        return candidates
            .compactMap { candidate in
                text.range(of: candidate, options: .caseInsensitive).map { (candidate, $0.lowerBound) }
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    nonisolated private static func annualCadence(in text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("/year")
            || lower.contains("per year")
            || lower.contains("por ano")
            || lower.contains("/ano")
            || lower.contains("anual")
            || lower.contains("annually")
    }

    nonisolated private static func nearbyText(around needle: String, in text: String, radius: Int) -> String {
        guard let range = text.range(of: needle, options: .caseInsensitive) else { return text }
        let lower = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[lower..<upper])
    }

    nonisolated private static func capture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }

    nonisolated private static func decimalNumber(_ raw: String, decimalSeparator: Character) -> Double? {
        var normalized = raw.replacingOccurrences(of: " ", with: "")
        if decimalSeparator == "," {
            normalized = normalized
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
        } else {
            normalized = normalized.replacingOccurrences(of: ",", with: "")
        }
        return Double(normalized)
    }
}
#endif
