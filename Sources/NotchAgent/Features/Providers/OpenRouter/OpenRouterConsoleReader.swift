import Foundation

#if os(macOS)
import SwiftUI
import WebKit

struct OpenRouterSpendStabilizer {
    private var lastValue: Double?
    private var consecutiveSamples = 0
    let minimumAttempt: Int

    init(minimumAttempt: Int = 3) {
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

/// Reads the account-wide "Past 1 Month" total rendered by OpenRouter's
/// Activity portal. Cookies stay inside the account's isolated WebKit store.
@MainActor
final class OpenRouterConsoleReader: NSObject, WKNavigationDelegate {
    private static let activityURL = URL(string: "https://openrouter.ai/activity")!
    private let accountID: UUID
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<AccountQuota?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var lastQuota: AccountQuota?
    private var stabilizer = OpenRouterSpendStabilizer()

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
        stabilizer = OpenRouterSpendStabilizer()
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
            configuration: APIAccountPortalSession.configuration(for: accountID)
        )
        view.navigationDelegate = self
        webView = view
        view.load(Self.freshRequest())
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                self?.finish(self?.lastQuota)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pollRenderedSpend(attempt: 0)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    private func pollRenderedSpend(attempt: Int) {
        guard let webView, continuation != nil else { return }
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] value, _ in
            guard let self else { return }
            if let text = value as? String, let quota = Self.parseActivityText(text) {
                self.lastQuota = quota
                if let spend = quota.monthlySpendUSD,
                   self.stabilizer.accepts(spend, attempt: attempt) {
                    self.finish(quota)
                    return
                }
            }
            guard attempt < 16 else {
                self.finish(self.lastQuota)
                return
            }
            self.pollTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.pollRenderedSpend(attempt: attempt + 1)
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
            url: activityURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 20
        )
        request.setValue("no-cache, no-store, must-revalidate", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }

    nonisolated static func parseActivityText(_ text: String, now: Date = Date()) -> AccountQuota? {
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        let pattern = #"(?is)\btotal\s+spend\b[\s\S]{0,120}?(?:US\s*)?\$\s*([0-9][0-9.,]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let range = Range(match.range(at: 1), in: normalized),
              let spend = decimalAmount(String(normalized[range]))
        else { return nil }

        let window = APIAccountSpendWindow.rolling30Days(endingAt: now)
        return AccountQuota(
            service: .openRouter,
            usedPercent: nil,
            resetsAt: nil,
            note: String(
                format: "OpenRouter Portal: last 30 days %.2f USD",
                locale: Locale(identifier: "en_US_POSIX"),
                spend
            ),
            monetaryUSD: spend,
            monetaryKind: .spend,
            monthlySpendUSD: spend,
            spendPeriod: .rolling30Days,
            spendWindowStart: window.start,
            spendWindowEnd: window.end
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
        if let comma {
            let decimals = raw.distance(from: raw.index(after: comma), to: raw.endIndex)
            return decimals == 2
                ? Double(raw.replacingOccurrences(of: ",", with: "."))
                : Double(raw.replacingOccurrences(of: ",", with: ""))
        }
        return Double(raw)
    }
}
#endif
