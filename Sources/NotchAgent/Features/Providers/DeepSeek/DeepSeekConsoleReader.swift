import Foundation

#if os(macOS)
import SwiftUI
import WebKit

/// Reads only the financial totals rendered by DeepSeek Platform. Login
/// cookies remain in WebKit's local website data store and are never copied
/// into Preferences, history, logs or the Keychain.
@MainActor
final class DeepSeekConsoleReader: NSObject, WKNavigationDelegate {
    private static let usageURL = URL(string: "https://platform.deepseek.com/usage")!
    private let accountID: UUID
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<AccountQuota?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var lastPartialQuota: AccountQuota?

    init(accountID: UUID) {
        self.accountID = accountID
    }

    static func makeLoginView(accountID: UUID) -> WKWebView {
        let view = WKWebView(
            frame: .zero,
            configuration: APIAccountPortalSession.configuration(for: accountID)
        )
        view.load(URLRequest(url: usageURL))
        return view
    }

    func fetchQuota() async -> AccountQuota? {
        finish(nil)
        lastPartialQuota = nil
        let view = WKWebView(
            // Some dashboard bundles defer usage cards when the viewport has
            // no layout area. Give the off-screen reader a real desktop size.
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
        Log.providers.info("deepseek console loaded \(webView.url?.path ?? "unknown", privacy: .public)")
        pollRenderedUsage(attempt: 0)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    private func pollRenderedUsage(attempt: Int) {
        guard let webView, continuation != nil else { return }
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] value, error in
            guard let self else { return }
            if let error {
                Log.providers.error("deepseek console DOM read failed: \(error.localizedDescription, privacy: .public)")
            }
            if let text = value as? String, let quota = Self.parseUsageText(text) {
                Log.providers.info(
                    "deepseek console poll \(attempt, privacy: .public): chars=\(text.count, privacy: .public) spend=\(quota.monthlySpendUSD != nil, privacy: .public) balance=\(quota.balanceUSD != nil, privacy: .public)"
                )
                self.lastPartialQuota = quota
                // The balance card renders before the usage cards. The API
                // already supplies balance, so wait for the console spend.
                if quota.monthlySpendUSD != nil {
                    self.finish(quota)
                    return
                }
            } else if let text = value as? String {
                Log.providers.info(
                    "deepseek console poll \(attempt, privacy: .public): chars=\(text.count, privacy: .public) no financial cards"
                )
            }
            guard attempt < 12 else {
                self.finish(self.lastPartialQuota)
                return
            }
            self.pollTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.pollRenderedUsage(attempt: attempt + 1)
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
        lastPartialQuota = nil
    }

    nonisolated static func parseUsageText(_ text: String, now: Date = Date()) -> AccountQuota? {
        let spend = labeledUSD("Cost", in: text)
        let balance = labeledUSD("Topped-up balance", in: text)
        guard spend != nil || balance != nil else { return nil }

        var parts: [String] = []
        if let spend {
            parts.append(String(format: "last 30 days %.2f USD", locale: Locale(identifier: "en_US_POSIX"), spend))
        }
        if let balance {
            parts.append(String(format: "balance %.2f USD", locale: Locale(identifier: "en_US_POSIX"), balance))
        }
        let window = APIAccountSpendWindow.rolling30Days(endingAt: now)
        return AccountQuota(
            service: .deepSeek,
            usedPercent: nil,
            resetsAt: nil,
            note: "DeepSeek Console: \(parts.joined(separator: " · "))",
            monetaryUSD: balance ?? spend,
            monetaryKind: balance == nil ? .spend : .balance,
            monthlySpendUSD: spend,
            spendPeriod: spend == nil ? nil : .rolling30Days,
            spendWindowStart: spend == nil ? nil : window.start,
            spendWindowEnd: spend == nil ? nil : window.end,
            balanceUSD: balance
        )
    }

    nonisolated private static func labeledUSD(_ label: String, in text: String) -> Double? {
        let normalizedText = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        let escaped = NSRegularExpression.escapedPattern(for: label)
        let pattern: String
        if label.caseInsensitiveCompare("Cost") == .orderedSame {
            // Exclude the lifetime "Total cost". Responsive layouts render
            // the selected window as either "Cost $6.21",
            // "Cost\n$6.21\nUSD", or "Cost(USD) $6.21".
            pattern = #"(?is)(?<!total )\bcost\b(?:\s*\(usd\))?[\s:]*\$\s*([0-9][0-9,.]*)\s*(?:USD\b)?"#
        } else {
            pattern = #"(?is)\b\#(escaped)\b[\s\S]{0,180}?\$\s*([0-9][0-9,.]*)\s*(?:USD\b)?"#
        }
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: normalizedText, range: NSRange(normalizedText.startIndex..., in: normalizedText)),
              let range = Range(match.range(at: 1), in: normalizedText)
        else { return nil }
        let amount = normalizedText[range].replacingOccurrences(of: ",", with: "")
        return Double(amount)
    }
}
#endif
