import Foundation

#if os(macOS)
import os
import SwiftUI
import WebKit

private struct XConsoleValueStabilizer {
    private var previous: Double?
    private var repetitions = 0

    mutating func accepts(_ value: Double, attempt: Int) -> Bool {
        if let previous, abs(previous - value) < 0.000_001 {
            repetitions += 1
        } else {
            previous = value
            repetitions = 1
        }
        return attempt >= 2 && repetitions >= 2
    }
}

/// Reads rolling 30-day spend and prepaid balance from the authenticated
/// X Developer Console. X's public usage endpoint exposes Post quota only.
/// Cookies remain inside the configured account's isolated WebKit profile.
@MainActor
final class XDeveloperConsoleReader: NSObject, WKNavigationDelegate {
    private static let logger = Logger(
        subsystem: "br.com.lfrprojects.notchagent",
        category: "x-developer-console"
    )
    private enum Phase {
        case locatingAccount
        case dashboard
        case usage
    }

    private static let consoleURL = URL(string: "https://console.x.com/")!
    private let accountID: UUID
    private var phase = Phase.locatingAccount
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<AccountQuota?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var balanceQuota: AccountQuota?
    private var spendQuota: AccountQuota?
    private var balanceStabilizer = XConsoleValueStabilizer()
    private var spendStabilizer = XConsoleValueStabilizer()

    init(accountID: UUID) {
        self.accountID = accountID
    }

    static func makeLoginView(accountID: UUID) -> WKWebView {
        let view = WKWebView(
            frame: .zero,
            configuration: APIAccountPortalSession.configuration(for: accountID)
        )
        view.load(freshRequest(url: consoleURL))
        return view
    }

    func fetchQuota() async -> AccountQuota? {
        finish(nil)
        phase = .locatingAccount
        balanceQuota = nil
        spendQuota = nil
        balanceStabilizer = XConsoleValueStabilizer()
        spendStabilizer = XConsoleValueStabilizer()

        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
            configuration: APIAccountPortalSession.configuration(for: accountID)
        )
        view.navigationDelegate = self
        webView = view
        view.load(Self.freshRequest(url: Self.consoleURL))

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled else { return }
                self?.finish(self?.mergedQuota())
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard continuation != nil else { return }
        Self.logger.info("Navigation finished: \(webView.url?.path ?? "missing", privacy: .public)")
        if Self.accountRoute(from: webView.url) != nil {
            if webView.url?.path.hasSuffix("/usage") == true {
                phase = .usage
                pollUsage(attempt: 0)
            } else {
                phase = .dashboard
                pollDashboard(attempt: 0)
            }
        } else {
            phase = .locatingAccount
            pollAccountRoute(attempt: 0)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(mergedQuota())
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(mergedQuota())
    }

    private func pollAccountRoute(attempt: Int) {
        guard phase == .locatingAccount, let webView, continuation != nil else { return }
        webView.evaluateJavaScript("window.location.href") { [weak self] value, _ in
            guard let self, self.phase == .locatingAccount else { return }
            if let rawURL = value as? String,
               let url = URL(string: rawURL),
               Self.accountRoute(from: url) != nil {
                Self.logger.info("Client-side account route detected: \(url.path, privacy: .public)")
                if url.path.hasSuffix("/usage") {
                    self.phase = .usage
                    self.pollUsage(attempt: 0)
                } else {
                    self.phase = .dashboard
                    self.pollDashboard(attempt: 0)
                }
                return
            }
            guard attempt < 15 else {
                Self.logger.info("Account route detection exhausted")
                self.finish(self.mergedQuota())
                return
            }
            self.schedule { [weak self] in self?.pollAccountRoute(attempt: attempt + 1) }
        }
    }

    private func pollDashboard(attempt: Int) {
        guard phase == .dashboard, let webView, continuation != nil else { return }
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] value, _ in
            guard let self, self.phase == .dashboard else { return }
            if let text = value as? String, let quota = Self.parseDashboardText(text) {
                self.balanceQuota = quota
                Self.logger.info("Dashboard balance parsed")
                if let balance = quota.balanceUSD,
                   self.balanceStabilizer.accepts(balance, attempt: attempt) {
                    self.openUsage()
                    return
                }
            }
            if attempt >= 7 {
                Self.logger.info("Dashboard parsing exhausted; continuing to usage")
                self.openUsage()
                return
            }
            self.schedule { [weak self] in self?.pollDashboard(attempt: attempt + 1) }
        }
    }

    private func openUsage() {
        guard phase == .dashboard,
              let webView,
              let route = Self.accountRoute(from: webView.url),
              let url = URL(string: "https://console.x.com\(route)/usage")
        else {
            finish(mergedQuota())
            return
        }
        phase = .usage
        pollTask?.cancel()
        webView.load(Self.freshRequest(url: url))
    }

    private func pollUsage(attempt: Int) {
        guard phase == .usage, let webView, continuation != nil else { return }
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] value, _ in
            guard let self, self.phase == .usage else { return }
            if let text = value as? String, let quota = Self.parseUsageText(text) {
                self.spendQuota = quota
                Self.logger.info("Usage spend parsed")
                if let spend = quota.monthlySpendUSD,
                   self.spendStabilizer.accepts(spend, attempt: attempt) {
                    self.finish(self.mergedQuota())
                    return
                }
            }
            guard attempt < 12 else {
                Self.logger.info("Usage parsing exhausted")
                self.finish(self.mergedQuota())
                return
            }
            self.schedule { [weak self] in self?.pollUsage(attempt: attempt + 1) }
        }
    }

    private func schedule(_ operation: @escaping @MainActor () -> Void) {
        pollTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            operation()
        }
    }

    private func mergedQuota() -> AccountQuota? {
        guard balanceQuota != nil || spendQuota != nil else { return nil }
        let spend = spendQuota?.monthlySpendUSD
        let balance = balanceQuota?.balanceUSD
        let details = [
            spend.map { String(format: "last 30 days %.2f USD", locale: Locale(identifier: "en_US_POSIX"), $0) },
            balance.map { String(format: "balance %.2f USD", locale: Locale(identifier: "en_US_POSIX"), $0) },
        ].compactMap { $0 }
        let consoleBillingScope = Self.accountRoute(from: webView?.url)
            .map { "x-console:\($0)" }
        return AccountQuota(
            service: .xTwitter,
            usedPercent: nil,
            resetsAt: nil,
            note: "X Developer Console: \(details.joined(separator: " · "))",
            monetaryUSD: balance ?? spend,
            monetaryKind: balance != nil ? .balance : .spend,
            monthlySpendUSD: spend,
            spendPeriod: spendQuota?.spendPeriod,
            spendWindowStart: spendQuota?.spendWindowStart,
            spendWindowEnd: spendQuota?.spendWindowEnd,
            balanceUSD: balance,
            billingScopeID: consoleBillingScope
        )
    }

    private func finish(_ quota: AccountQuota?) {
        Self.logger.info(
            "Reader finished: spend=\(quota?.monthlySpendUSD != nil, privacy: .public) balance=\(quota?.balanceUSD != nil, privacy: .public)"
        )
        timeoutTask?.cancel()
        pollTask?.cancel()
        timeoutTask = nil
        pollTask = nil
        continuation?.resume(returning: quota)
        continuation = nil
        webView = nil
    }

    private static func freshRequest(url: URL) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 20
        )
        request.setValue("no-cache, no-store, must-revalidate", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }

    nonisolated static func accountRoute(from url: URL?) -> String? {
        guard let components = url?.pathComponents,
              let accountIndex = components.firstIndex(of: "accounts"),
              components.indices.contains(accountIndex + 1)
        else { return nil }
        let account = components[accountIndex + 1]
        guard !account.isEmpty else { return nil }
        return "/accounts/\(account)"
    }

    nonisolated static func parseDashboardText(_ text: String) -> AccountQuota? {
        guard let balance = amount(
            in: text,
            labels: ["Credit remaining", "Total Balance", "Saldo Total", "Crédito restante"]
        ) else { return nil }
        return AccountQuota(
            service: .xTwitter,
            usedPercent: nil,
            resetsAt: nil,
            note: String(
                format: "X Developer Console balance: %.2f USD",
                locale: Locale(identifier: "en_US_POSIX"),
                balance
            ),
            monetaryUSD: balance,
            monetaryKind: .balance,
            balanceUSD: balance
        )
    }

    nonisolated static func parseUsageText(_ text: String, now: Date = Date()) -> AccountQuota? {
        guard let spend = amount(
            in: text,
            labels: ["Total Cost", "Custo Total", "Costo Total"]
        ) else { return nil }
        let window = APIAccountSpendWindow.rolling30Days(endingAt: now)
        return AccountQuota(
            service: .xTwitter,
            usedPercent: nil,
            resetsAt: nil,
            note: String(
                format: "X Developer Console last 30 days: %.2f USD",
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

    nonisolated private static func amount(in text: String, labels: [String]) -> Double? {
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        for label in labels {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let patterns = [
                #"(?is)\#(escaped)[\s\S]{0,180}?(?:US\s*)?\$\s*([0-9][0-9.,]*)"#,
                #"(?is)(?:US\s*)?\$\s*([0-9][0-9.,]*)[\s\S]{0,100}?\#(escaped)"#,
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(
                        in: normalized,
                        range: NSRange(normalized.startIndex..., in: normalized)
                      ),
                      let range = Range(match.range(at: 1), in: normalized),
                      let value = decimalAmount(String(normalized[range]))
                else { continue }
                return value
            }
        }
        return nil
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
