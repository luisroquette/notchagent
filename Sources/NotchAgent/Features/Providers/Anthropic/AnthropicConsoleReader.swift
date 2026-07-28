import Foundation

#if os(macOS)
import SwiftUI
import WebKit

/// Reads the authenticated Claude subscription billing page. Cookies stay in
/// the account-specific WebKit store; no Claude credential is copied out.
@MainActor
final class AnthropicConsoleReader: NSObject, WKNavigationDelegate {
    private static let usageURL = URL(string: "https://claude.ai/settings/usage")!
    private static let teamBillingURL = URL(string: "https://claude.ai/admin-settings/billing")!
    private static let personalBillingURL = URL(string: "https://claude.ai/settings/billing")!
    private let accountID: UUID
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<AccountQuota?, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var attemptedPersonalBilling = false
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
        attemptedPersonalBilling = false
        lastPartialQuota = nil
        let view = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1200, height: 900),
            configuration: APIAccountPortalSession.configuration(for: accountID)
        )
        view.navigationDelegate = self
        webView = view
        view.load(URLRequest(url: Self.teamBillingURL))
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
        Log.providers.info(
            "claude billing loaded \(webView.url?.path ?? "unknown", privacy: .public)"
        )
        pollBilling(attempt: 0)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        tryPersonalBilling()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        tryPersonalBilling()
    }

    private func pollBilling(attempt: Int) {
        guard let webView, continuation != nil else { return }
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] value, _ in
            guard let self else { return }
            if let text = value as? String, let quota = Self.parseBillingText(text) {
                self.lastPartialQuota = quota
                Log.providers.info(
                    "claude billing parsed attempt=\(attempt, privacy: .public) chars=\(text.count, privacy: .public)"
                )
                // Billing cards hydrate independently. Do not stop on the
                // projected invoice while seats/usage-credit balance are
                // still being painted.
                if quota.balanceBRL != nil || quota.seatCount != nil || attempt >= 8 {
                    self.finish(quota)
                    return
                }
            }
            if let text = value as? String {
                Log.providers.info(
                    "claude billing waiting attempt=\(attempt, privacy: .public) chars=\(text.count, privacy: .public) path=\(webView.url?.path ?? "unknown", privacy: .public)"
                )
            }
            guard attempt < 8 else {
                if let lastPartialQuota {
                    self.finish(lastPartialQuota)
                } else {
                    self.tryPersonalBilling()
                }
                return
            }
            self.pollTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.pollBilling(attempt: attempt + 1)
            }
        }
    }

    private func tryPersonalBilling() {
        guard continuation != nil else { return }
        pollTask?.cancel()
        pollTask = nil
        guard !attemptedPersonalBilling, let webView else {
            finish(nil)
            return
        }
        attemptedPersonalBilling = true
        Log.providers.info("claude team billing unavailable; trying personal billing")
        webView.load(URLRequest(url: Self.personalBillingURL))
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

    nonisolated static func parseBillingText(_ text: String) -> AccountQuota? {
        let projected = labeledBRL(
            labels: ["Total projetado", "Projected total", "Próxima fatura", "Next invoice"],
            in: text
        )
        guard let projected else { return nil }

        let balance = usageCreditBalance(in: text)
        let plan = capturedText(
            pattern: #"(?is)(?:Plano atual|Current plan)\s+(?:plano\s+)?([^\n]+?)(?:\s+Licenças|\s+Seats|\n)"#,
            in: text
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let seats = capturedText(
            pattern: #"(?is)(?:Quantidade de licenças|Licenças|Seat quantity|Total seats)\s+([0-9]+)"#,
            in: text
        ).flatMap(Int.init)

        var details = ["próxima fatura \(currencyText(projected))"]
        if let plan, !plan.isEmpty { details.insert("plano \(plan)", at: 0) }
        if let seats { details.append("\(seats) licenças") }
        if let balance { details.append("créditos de uso \(currencyText(balance))") }

        return AccountQuota(
            service: .anthropicConsole,
            usedPercent: nil,
            resetsAt: nil,
            note: "Claude: \(details.joined(separator: " · "))",
            monthlyPlanBRL: projected,
            balanceBRL: balance,
            planName: plan,
            seatCount: seats
        )
    }

    nonisolated private static func labeledBRL(labels: [String], in text: String) -> Decimal? {
        let escaped = labels.map(NSRegularExpression.escapedPattern).joined(separator: "|")
        let pattern = #"(?is)(?:\#(escaped))[\s\S]{0,120}?(?:-\s*)?R\$\s*([0-9][0-9.\s]*,[0-9]{2})"#
        guard let raw = capturedText(pattern: pattern, in: text) else { return nil }
        return decimalBRL(raw)
    }

    nonisolated private static func usageCreditBalance(in text: String) -> Decimal? {
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        let patterns = [
            #"(?is)(?:Créditos de uso|Usage credits)[\s\S]{0,360}?(-\s*)?R\$\s*([0-9][0-9.\s]*,[0-9]{2})[\s\S]{0,80}?(?:Saldo atual|Current balance)"#,
            #"(?is)(?:Créditos de uso|Usage credits)[\s\S]{0,360}?(?:Saldo atual|Current balance)[\s\S]{0,80}?(-\s*)?R\$\s*([0-9][0-9.\s]*,[0-9]{2})"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: normalized,
                    range: NSRange(normalized.startIndex..., in: normalized)
                  ),
                  let amountRange = Range(match.range(at: 2), in: normalized),
                  let amount = decimalBRL(String(normalized[amountRange]))
            else { continue }
            return match.range(at: 1).location != NSNotFound ? -amount : amount
        }
        return nil
    }

    nonisolated private static func decimalBRL(_ raw: String) -> Decimal? {
        let normalized = raw
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    nonisolated private static func capturedText(pattern: String, in text: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: normalized,
                range: NSRange(normalized.startIndex..., in: normalized)
              ),
              let range = Range(match.range(at: match.numberOfRanges - 1), in: normalized)
        else { return nil }
        return String(normalized[range])
    }

    nonisolated private static func currencyText(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "BRL"
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "R$ —"
    }
}
#endif
