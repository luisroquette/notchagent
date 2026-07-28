import Foundation

#if os(macOS)
import WebKit

/// Reads the authenticated Firecrawl billing page. The Firecrawl API account
/// remains responsible for credits; this reader only reports the recurring
/// website subscription.
@MainActor
final class FirecrawlSubscriptionReader: NSObject, WKNavigationDelegate {
    private static let dashboardURL = URL(string: "https://www.firecrawl.dev/app")!
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
        view.load(URLRequest(url: dashboardURL))
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
        view.load(URLRequest(url: Self.dashboardURL))
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
          const body = document.body ? document.body.innerText : '';
          if (!/(current plan|your plan|plano atual|seu plano)/i.test(body)) {
            const target = [...document.querySelectorAll('a,button')].find((element) =>
              /^(billing|faturamento|subscription|assinatura|manage plan)$/i
                .test((element.innerText || '').trim())
            );
            if (target) target.click();
          }
          return body;
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            guard let self else { return }
            if let text = value as? String, let quota = Self.parseBillingText(text) {
                Log.providers.info("firecrawl subscription parsed chars=\(text.count, privacy: .public)")
                self.finish(quota)
                return
            }
            guard attempt < 12 else {
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
        guard let plan = currentPlan(in: normalized) else { return nil }
        let scope = forwardText(after: plan, in: normalized, radius: 550)
        guard let amount = recurringAmount(in: scope) else { return nil }
        let renewal = renewalDate(in: scope)

        return AccountQuota(
            service: .firecrawlSubscription,
            usedPercent: nil,
            resetsAt: renewal,
            note: "Firecrawl: plano \(plan) · \(amount.isAnnual ? "equivalente mensal" : "mensal")",
            monthlyPlanUSD: amount.currency == .usd ? amount.monthlyValue : nil,
            monthlyPlanBRL: amount.currency == .brl ? Decimal(amount.monthlyValue) : nil,
            planName: plan
        )
    }

    private enum Currency {
        case brl
        case usd
    }

    private struct RecurringAmount {
        let currency: Currency
        let monthlyValue: Double
        let isAnnual: Bool
    }

    nonisolated private static func currentPlan(in text: String) -> String? {
        let plan = #"(Free|Hobby|Standard|Growth|Scale|Enterprise)"#
        let patterns = [
            #"(?is)(?:current|your)\s+plan[^\n]{0,30}\n?\s*"# + plan,
            #"(?is)"# + plan + #"[^\n]{0,30}\n?\s*(?:current|your)\s+plan"#,
            #"(?is)(?:plano\s+atual|seu\s+plano)[^\n]{0,30}\n?\s*"# + plan,
            #"(?is)"# + plan + #"[^\n]{0,30}\n?\s*(?:plano\s+atual|seu\s+plano)"#,
        ]
        for pattern in patterns {
            if let value = capture(pattern: pattern, in: text, group: 1) {
                return value.prefix(1).uppercased() + value.dropFirst().lowercased()
            }
        }
        return nil
    }

    nonisolated private static func recurringAmount(in text: String) -> RecurringAmount? {
        let annual = containsAnnualCadence(text)
        guard annual || containsMonthlyCadence(text) else { return nil }
        let divisor = annual ? 12.0 : 1.0

        if let raw = capture(
            pattern: #"(?i)R\$\s*([0-9][0-9.\s]*(?:,[0-9]{1,2})?)"#,
            in: text
        ), let value = decimalNumber(raw, decimalSeparator: ",") {
            return RecurringAmount(currency: .brl, monthlyValue: value / divisor, isAnnual: annual)
        }
        if let raw = capture(
            pattern: #"(?i)(?:US\s*\$|USD\s*|\$)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#,
            in: text
        ), let value = decimalNumber(raw, decimalSeparator: ".") {
            return RecurringAmount(currency: .usd, monthlyValue: value / divisor, isAnnual: annual)
        }
        return nil
    }

    nonisolated private static func containsAnnualCadence(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("/year")
            || lower.contains("/yr")
            || lower.contains("/ year")
            || lower.contains("/ yr")
            || lower.contains("per year")
            || lower.contains("por ano")
            || lower.contains("/ano")
            || lower.contains("/ ano")
            || lower.contains("annually")
            || lower.contains("anual")
    }

    nonisolated private static func containsMonthlyCadence(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("/month")
            || lower.contains("/mo")
            || lower.contains("/ month")
            || lower.contains("/ mo")
            || lower.contains("per month")
            || lower.contains("por mês")
            || lower.contains("/mês")
            || lower.contains("/ mês")
            || lower.contains("monthly")
            || lower.contains("mensal")
    }

    nonisolated private static func renewalDate(in text: String) -> Date? {
        let patterns = [
            #"(?i)(?:renews?\s+(?:on\s+)?|renewal\s+(?:date\s*)?:?\s*|next\s+billing\s+(?:date\s*)?:?\s*)([A-Za-zÀ-ÿ.]+\s+\d{1,2},?\s+\d{4})"#,
            #"(?i)(?:renova\s+em|próxima\s+cobrança\s*:?)\s*(\d{1,2}\s+de\s+[A-Za-zÀ-ÿ.]+\s+de\s+\d{4})"#,
        ]
        for pattern in patterns {
            guard let raw = capture(pattern: pattern, in: text) else { continue }
            for localeID in ["en_US_POSIX", "pt_BR"] {
                for format in ["MMMM d, yyyy", "MMM d, yyyy", "d 'de' MMMM 'de' yyyy", "d 'de' MMM. 'de' yyyy"] {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: localeID)
                    formatter.timeZone = TimeZone(secondsFromGMT: 0)
                    formatter.dateFormat = format
                    if let date = formatter.date(from: raw) { return date }
                }
            }
        }
        return nil
    }

    nonisolated private static func forwardText(after needle: String, in text: String, radius: Int) -> String {
        guard let range = text.range(of: needle, options: .caseInsensitive) else { return text }
        let upper = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[range.lowerBound..<upper])
    }

    nonisolated private static func capture(pattern: String, in text: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > group,
              let range = Range(match.range(at: group), in: text)
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
