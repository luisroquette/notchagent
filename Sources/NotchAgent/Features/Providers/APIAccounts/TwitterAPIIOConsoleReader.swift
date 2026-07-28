import Foundation

#if os(macOS)
import SwiftUI
import WebKit

/// Reads the 30-day credit consumption used by twitterapi.io's own dashboard.
/// The portal bearer token never leaves the isolated WebKit page.
@MainActor
final class TwitterAPIIOConsoleReader: NSObject, WKNavigationDelegate {
    private static let dashboardURL = URL(string: "https://twitterapi.io/dashboard")!
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
        view.load(freshRequest())
        return view
    }

    func fetchQuota() async -> AccountQuota? {
        finish(nil)
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1400, height: 1000),
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
                self?.finish(nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pollPortalData(attempt: 0)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    private func pollPortalData(attempt: Int) {
        guard let webView, continuation != nil else { return }
        webView.evaluateJavaScript(Self.portalReadScript) { [weak self] value, _ in
            guard let self else { return }
            if let json = value as? String,
               let data = json.data(using: .utf8),
               let quota = Self.parsePortalPayload(data) {
                self.finish(quota)
                return
            }
            guard attempt < 16 else {
                self.finish(nil)
                return
            }
            self.pollTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.pollPortalData(attempt: attempt + 1)
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

    private static func freshRequest() -> URLRequest {
        var request = URLRequest(
            url: dashboardURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 20
        )
        request.setValue("no-cache, no-store, must-revalidate", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }

    /// Starts authenticated reads inside the page and returns only non-secret
    /// billing JSON. The NextAuth access token remains a JavaScript local.
    private static let portalReadScript = """
    (() => {
      const root = document.documentElement;
      const attribute = 'data-notchagent-twitterapiio';
      const existing = root.getAttribute(attribute);
      if (existing) return existing;
      if (!window.__notchAgentTwitterAPIIORead) {
        window.__notchAgentTwitterAPIIORead = true;
        fetch('/api/auth/session', { cache: 'no-store', credentials: 'include' })
          .then(response => response.json())
          .then(session => {
            if (!session.accessToken) throw new Error('unauthenticated');
            const headers = { Authorization: `Bearer ${session.accessToken}` };
            return Promise.all([
              fetch('https://api.twitterapi.io/backend/user/consumption_summary', {
                cache: 'no-store',
                headers
              }).then(response => response.json()),
              fetch('https://api.twitterapi.io/backend/user/billing/summary', {
                cache: 'no-store',
                headers
              }).then(response => response.json())
            ]);
          })
          .then(([consumption, billing]) => {
            root.setAttribute(attribute, JSON.stringify({ consumption, billing }));
          })
          .catch(() => {
            root.setAttribute(attribute, '{}');
          });
      }
      return '';
    })()
    """

    nonisolated static func parsePortalPayload(_ data: Data, now: Date = Date()) -> AccountQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let consumptionResponse = root["consumption"] as? [String: Any]
        let consumptionData = consumptionResponse?["data"] as? [String: Any]
        let window30Days = consumptionData?["window_30d"] as? [String: Any]
        let credits = window30Days.flatMap { numericValue($0["credits_consumed"]) }
        let calls = window30Days.flatMap { numericValue($0["calls"]) }

        let billingResponse = root["billing"] as? [String: Any]
        let billingData = billingResponse?["data"] as? [String: Any]
        let balanceCents = billingData.flatMap { numericValue($0["current_balance_cents"]) }

        let spendUSD = credits.map { max($0, 0) / 100_000 }
        let balanceUSD = balanceCents.map { max($0, 0) / 100 }
        guard spendUSD != nil || balanceUSD != nil else { return nil }

        var details: [String] = []
        if let credits, let spendUSD {
            var usage = String(
                format: "last 30 days %.0f credits = %.2f USD",
                locale: Locale(identifier: "en_US_POSIX"),
                credits,
                spendUSD
            )
            if let calls {
                usage += String(
                    format: " across %.0f calls",
                    locale: Locale(identifier: "en_US_POSIX"),
                    calls
                )
            }
            details.append(usage)
        }
        if let balanceUSD {
            details.append(String(
                format: "balance %.2f USD",
                locale: Locale(identifier: "en_US_POSIX"),
                balanceUSD
            ))
        }

        let window = APIAccountSpendWindow.rolling30Days(endingAt: now)
        return AccountQuota(
            service: .twitterAPI,
            usedPercent: nil,
            resetsAt: nil,
            note: "twitterapi.io Portal: \(details.joined(separator: " · "))",
            monetaryUSD: balanceUSD ?? spendUSD,
            monetaryKind: balanceUSD == nil ? .spend : .balance,
            monthlySpendUSD: spendUSD,
            spendPeriod: spendUSD == nil ? nil : .rolling30Days,
            spendWindowStart: spendUSD == nil ? nil : window.start,
            spendWindowEnd: spendUSD == nil ? nil : window.end,
            balanceUSD: balanceUSD,
            cycleUsed: credits,
            cycleUnit: credits == nil ? nil : "créditos consumidos em 30 dias"
        )
    }

    nonisolated private static func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            number.doubleValue
        case let string as String:
            Double(string)
        default:
            nil
        }
    }
}
#endif
