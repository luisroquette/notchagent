import Foundation

#if os(macOS)
import SwiftUI
import WebKit

/// Reads the rolling 28-day Gemini API cost rendered by Google AI Studio.
/// Login cookies stay inside the account's isolated WebKit store.
@MainActor
final class GoogleAIStudioConsoleReader: NSObject, WKNavigationDelegate {
    private let accountID: UUID
    private let projectID: String
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<AccountQuota?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var lastQuota: AccountQuota?
    private var brlPerUSD: Double?

    init(accountID: UUID, projectID: String) {
        self.accountID = accountID
        self.projectID = projectID
    }

    static func makeLoginView(accountID: UUID, projectID: String) -> WKWebView {
        let view = WKWebView(
            frame: .zero,
            configuration: APIAccountPortalSession.configuration(for: accountID)
        )
        if let url = spendURL(projectID: projectID) {
            view.load(URLRequest(url: url))
        }
        return view
    }

    func fetchQuota(brlPerUSD: Double?) async -> AccountQuota? {
        finish(nil)
        lastQuota = nil
        guard let brlPerUSD, brlPerUSD > 0,
              let url = Self.spendURL(projectID: projectID)
        else { return nil }
        self.brlPerUSD = brlPerUSD
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
            configuration: APIAccountPortalSession.configuration(for: accountID)
        )
        view.navigationDelegate = self
        webView = view
        view.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
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
            if let text = value as? String,
               let quota = Self.parseSpendText(
                   text,
                   projectID: self.projectID,
                   brlPerUSD: self.brlPerUSD ?? 0
               ) {
                self.lastQuota = quota
                self.finish(quota)
                return
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
        brlPerUSD = nil
    }

    private static func spendURL(projectID: String) -> URL? {
        guard !projectID.isEmpty else { return nil }
        var components = URLComponents(string: "https://aistudio.google.com/app/spend")
        components?.queryItems = [URLQueryItem(name: "project", value: projectID)]
        return components?.url
    }

    nonisolated static func parseSpendText(
        _ text: String,
        projectID: String,
        brlPerUSD: Double,
        now: Date = Date()
    ) -> AccountQuota? {
        guard brlPerUSD > 0 else { return nil }
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        guard normalized.range(
            of: #"\b28\s+(?:dias|days)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil else { return nil }
        let pattern = #"(?is)(?:seu\s+custo\s+total|your\s+total\s+cost)[\s\S]{0,700}?(?:custo\s+total|total\s+cost)\s*R\$\s*([0-9][0-9.,]*)([KkMm]?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let amountRange = Range(match.range(at: 1), in: normalized),
              let amount = decimalAmount(String(normalized[amountRange]))
        else { return nil }
        let suffix = Range(match.range(at: 2), in: normalized).map { String(normalized[$0]).lowercased() } ?? ""
        let multiplier: Double = suffix == "k" ? 1_000 : (suffix == "m" ? 1_000_000 : 1)
        let spendBRL = amount * multiplier
        let spendUSD = spendBRL / brlPerUSD
        let window = APIAccountSpendWindow.rolling28Days(endingAt: now)
        return AccountQuota(
            service: .gemini,
            usedPercent: nil,
            resetsAt: nil,
            note: String(
                format: "Google AI Studio: last 28 days R$ %.2f",
                locale: Locale(identifier: "en_US_POSIX"),
                spendBRL
            ),
            monetaryUSD: spendUSD,
            monetaryKind: .spend,
            monthlySpendUSD: spendUSD,
            monthlySpendBRL: Decimal(spendBRL),
            spendPeriod: .rolling28Days,
            spendWindowStart: window.start,
            spendWindowEnd: window.end,
            billingScopeID: "google-project:\(projectID)"
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
