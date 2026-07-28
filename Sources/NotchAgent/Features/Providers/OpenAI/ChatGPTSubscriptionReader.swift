import Foundation

#if os(macOS)
import WebKit

/// Reads the authenticated ChatGPT billing surface. The browser profile is
/// isolated from OpenAI API billing and no credential leaves WebKit.
@MainActor
final class ChatGPTSubscriptionReader: NSObject, WKNavigationDelegate {
    private static let billingURL = URL(string: "https://chatgpt.com/#settings/Billing")!
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
        view.load(URLRequest(url: billingURL))
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
        view.load(URLRequest(url: Self.billingURL))
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
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] value, _ in
            guard let self else { return }
            if let text = value as? String, let quota = Self.parseBillingText(text) {
                Log.providers.info("chatgpt subscription parsed chars=\(text.count, privacy: .public)")
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
        let normalized = normalizedText(text)
        guard let plan = chatGPTPlan(in: normalized) else { return nil }
        let scope = nearbyText(around: plan, in: normalized, radius: 700)
        guard let amount = recurringAmount(in: scope) ?? recurringAmount(in: normalized) else {
            return nil
        }

        let cadence = annualCadence(in: scope) ? "equivalente mensal" : "mensal"
        return AccountQuota(
            service: .chatGPTSubscription,
            usedPercent: nil,
            resetsAt: nil,
            note: "ChatGPT: plano \(plan) · \(cadence)",
            monthlyPlanUSD: amount.currency == .usd ? amount.monthlyValue : nil,
            monthlyPlanBRL: amount.currency == .brl ? amount.monthlyDecimal : nil,
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

        var monthlyDecimal: Decimal {
            Decimal(monthlyValue)
        }
    }

    nonisolated private static func recurringAmount(in text: String) -> RecurringAmount? {
        let isAnnual = annualCadence(in: text)
        let divisor = isAnnual ? 12.0 : 1.0
        if let raw = capture(
            pattern: #"(?i)R\$\s*([0-9][0-9.\s]*(?:,[0-9]{1,2})?)"#,
            in: text
        ), let value = decimalNumber(raw, decimalSeparator: ",") {
            return RecurringAmount(currency: .brl, monthlyValue: value / divisor)
        }
        if let raw = capture(
            pattern: #"(?i)(?:US\s*\$|USD\s*|\$)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#,
            in: text
        ), let value = decimalNumber(raw, decimalSeparator: ".") {
            return RecurringAmount(currency: .usd, monthlyValue: value / divisor)
        }
        return nil
    }

    nonisolated private static func chatGPTPlan(in text: String) -> String? {
        if let exact = capture(
            pattern: #"(?im)^[\t ]*(ChatGPT[\t ]+(?:Business|Enterprise|Team|Pro|Plus|Go)(?:[\t ]+[^\n]{1,30})?)[\t ]*$"#,
            in: text
        ) {
            return exact.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let candidates = [
            "ChatGPT Business",
            "ChatGPT Enterprise",
            "ChatGPT Team",
            "ChatGPT Pro",
            "ChatGPT Plus",
            "ChatGPT Go",
        ]
        return candidates.first { text.localizedCaseInsensitiveContains($0) }
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

    nonisolated private static func normalizedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
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
