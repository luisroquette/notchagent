import Foundation

#if os(macOS)
import SwiftUI
import WebKit

struct OpenAIBalanceStabilizer {
    private var lastValue: Double?
    private var consecutiveSamples = 0
    let minimumAttempt: Int

    init(minimumAttempt: Int = 5) {
        self.minimumAttempt = minimumAttempt
    }

    mutating func accepts(_ value: Double, attempt: Int) -> Bool {
        if let lastValue, abs(lastValue - value) < 0.000_001 {
            consecutiveSamples += 1
        } else {
            lastValue = value
            consecutiveSamples = 1
        }
        return attempt >= minimumAttempt && consecutiveSamples >= 2
    }
}

/// Reads only the prepaid credit balance rendered by OpenAI's billing portal.
/// Authentication stays inside the account's isolated WebKit data store.
@MainActor
final class OpenAIConsoleReader: NSObject, WKNavigationDelegate {
    private static let billingURL = URL(string: "https://platform.openai.com/settings/organization/billing/overview")!
    private let accountID: UUID
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<AccountQuota?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var lastQuota: AccountQuota?
    private var balanceStabilizer = OpenAIBalanceStabilizer()

    init(accountID: UUID) {
        self.accountID = accountID
    }

    static func makeLoginView(accountID: UUID) -> WKWebView {
        let view = WKWebView(
            frame: .zero,
            configuration: APIAccountPortalSession.configuration(for: accountID)
        )
        view.load(freshRequest())
        return view
    }

    func fetchQuota() async -> AccountQuota? {
        finish(nil)
        lastQuota = nil
        balanceStabilizer = OpenAIBalanceStabilizer()
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1200, height: 900),
            configuration: APIAccountPortalSession.configuration(for: accountID)
        )
        view.navigationDelegate = self
        webView = view
        view.load(Self.freshRequest())
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { return }
                self?.finish(nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pollRenderedBalance(attempt: 0)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    private func pollRenderedBalance(attempt: Int) {
        guard let webView, continuation != nil else { return }
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] value, _ in
            guard let self else { return }
            if let text = value as? String, let quota = Self.parseBillingText(text) {
                self.lastQuota = quota
                if let balance = quota.balanceUSD,
                   self.balanceStabilizer.accepts(balance, attempt: attempt) {
                    self.finish(quota)
                    return
                }
            }
            guard attempt < 10 else {
                self.finish(self.lastQuota)
                return
            }
            self.pollTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.pollRenderedBalance(attempt: attempt + 1)
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
        lastQuota = nil
    }

    private static func freshRequest() -> URLRequest {
        var request = URLRequest(
            url: billingURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 15
        )
        request.setValue("no-cache, no-store, must-revalidate", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }

    nonisolated static func parseBillingText(_ text: String) -> AccountQuota? {
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        let labels = [
            "credit balance",
            "prepaid balance",
            "free trial credit remaining",
            "credits remaining",
            "saldo de créditos",
            "saldo pré-pago",
            "crédito restante",
        ]
        let labelPattern = labels.map(NSRegularExpression.escapedPattern).joined(separator: "|")
        let pattern = #"(?is)(?:\#(labelPattern))[\s\S]{0,120}?(?:US\s*\$|\$)\s*([0-9][0-9.,]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let range = Range(match.range(at: 1), in: normalized),
              let balance = decimalAmount(String(normalized[range]))
        else { return nil }

        return AccountQuota(
            service: .openAI,
            usedPercent: nil,
            resetsAt: nil,
            note: String(format: "OpenAI prepaid balance: %.2f USD", locale: Locale(identifier: "en_US_POSIX"), balance),
            monetaryUSD: balance,
            monetaryKind: .balance,
            balanceUSD: balance
        )
    }

    nonisolated private static func decimalAmount(_ raw: String) -> Double? {
        let comma = raw.lastIndex(of: ",")
        let dot = raw.lastIndex(of: ".")
        if let comma, let dot {
            if comma > dot {
                return Double(raw.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."))
            }
            return Double(raw.replacingOccurrences(of: ",", with: ""))
        }
        if comma != nil {
            return Double(raw.replacingOccurrences(of: ",", with: "."))
        }
        return Double(raw)
    }
}
#endif
