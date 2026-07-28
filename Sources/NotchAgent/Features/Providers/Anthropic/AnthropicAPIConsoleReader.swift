import Foundation

#if os(macOS)
import SwiftUI
import WebKit

/// Reads the current calendar month's API cost rendered by Claude Console.
/// Authentication cookies stay inside the isolated WebKit data store.
@MainActor
final class AnthropicAPIConsoleReader: NSObject, WKNavigationDelegate {
    private static let costURL = URL(string: "https://platform.claude.com/cost")!
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
        view.load(URLRequest(url: costURL))
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
        view.load(URLRequest(url: Self.costURL))
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
            "anthropic API console loaded \(webView.url?.path ?? "unknown", privacy: .public)"
        )
        pollRenderedCost(attempt: 0)
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

    private func pollRenderedCost(attempt: Int) {
        guard let webView, continuation != nil else { return }
        webView.evaluateJavaScript(Self.costCardJavaScript) { [weak self] value, error in
            guard let self else { return }
            if let error {
                Log.providers.error(
                    "anthropic API console DOM read failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            if let text = value as? String,
               let quota = Self.parseCostText(text) {
                self.finish(quota)
                return
            }
            guard attempt < 15 else {
                self.finish(nil)
                return
            }
            self.pollTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.pollRenderedCost(attempt: attempt + 1)
            }
        }
    }

    /// Returns the smallest rendered card containing the exact total-cost
    /// label and a currency value. This prevents the sidebar's prepaid
    /// "Credits" amount from being mistaken for spend.
    private static let costCardJavaScript = """
    (() => {
      const headings = Array.from(
        document.querySelectorAll("h1, h2, h3, h4, h5, h6, [role='heading']")
      );
      let costCard = "";
      for (const element of headings) {
        const ownText = (element.innerText || "")
          .replace(/\\s+/g, " ")
          .trim()
          .toLowerCase();
        const isPortugueseTotal =
          ownText.startsWith("custo total") && !ownText.startsWith("custo total de");
        const isEnglishTotal =
          ownText.startsWith("total cost") &&
          !ownText.startsWith("total cost of") &&
          !ownText.startsWith("total token cost");
        const isSpendTotal =
          ownText.startsWith("total spend") || ownText.startsWith("gasto total");
        if (!isPortugueseTotal && !isEnglishTotal && !isSpendTotal) continue;
        let candidate = element;
        for (let depth = 0; depth < 6 && candidate; depth += 1) {
          const text = (candidate.innerText || "").trim();
          if (text.length <= 600 && /(?:US\\$|USD|\\$)\\s*[0-9]/i.test(text)) {
            costCard = text;
            break;
          }
          candidate = candidate.parentElement;
        }
        if (costCard) break;
      }

      let creditsCard = "";
      const elements = Array.from(document.querySelectorAll("body *"));
      for (const element of elements) {
        const ownText = (element.innerText || "")
          .replace(/\\s+/g, " ")
          .trim()
          .toLowerCase();
        if (
          ownText !== "credits" &&
          ownText !== "créditos" &&
          !ownText.startsWith("credits us$") &&
          !ownText.startsWith("créditos us$")
        ) continue;
        let candidate = element;
        for (let depth = 0; depth < 5 && candidate; depth += 1) {
          const text = (candidate.innerText || "").trim();
          if (text.length <= 300 && /(?:US\\$|USD|\\$)\\s*[0-9]/i.test(text)) {
            creditsCard = text;
            break;
          }
          candidate = candidate.parentElement;
        }
        if (creditsCard) break;
      }

      return [costCard, creditsCard].filter(Boolean).join("\\n__NOTCH_CREDITS__\\n");
    })()
    """

    private func finish(_ quota: AccountQuota?) {
        timeoutTask?.cancel()
        pollTask?.cancel()
        timeoutTask = nil
        pollTask = nil
        continuation?.resume(returning: quota)
        continuation = nil
        webView = nil
    }

    nonisolated static func parseCostText(
        _ text: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AccountQuota? {
        guard let spend = labeledCost(in: text) else { return nil }
        let balance = labeledCreditBalance(in: text)
        let window = APIAccountSpendWindow.currentCalendarMonth(
            endingAt: now,
            calendar: calendar
        )
        var parts = [
            String(
                format: "custo do mês atual %.2f USD",
                locale: Locale(identifier: "en_US_POSIX"),
                spend
            ),
        ]
        if let balance {
            parts.append(
                String(
                    format: "saldo %.2f USD",
                    locale: Locale(identifier: "en_US_POSIX"),
                    balance
                )
            )
        }
        return AccountQuota(
            service: .anthropicAPI,
            usedPercent: nil,
            resetsAt: nil,
            note: "Anthropic Console: \(parts.joined(separator: " · "))",
            monetaryUSD: balance ?? spend,
            monetaryKind: balance == nil ? .spend : .balance,
            monthlySpendUSD: spend,
            spendPeriod: .currentCalendarMonth,
            spendWindowStart: window.start,
            spendWindowEnd: window.end,
            balanceUSD: balance
        )
    }

    nonisolated private static func labeledCost(in text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r", with: "\n")
        let patterns = [
            #"(?is)\b(?:total\s+cost|custo\s+total|total\s+spend|gasto\s+total)\b[\s\S]{0,500}?(?:US\$\s*|\$\s*|USD\s*)([0-9][0-9.,]*)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: normalized,
                    range: NSRange(normalized.startIndex..., in: normalized)
                  ),
                  let range = Range(match.range(at: 1), in: normalized),
                  let amount = decimalAmount(String(normalized[range]))
            else { continue }
            return amount
        }
        return nil
    }

    nonisolated private static func labeledCreditBalance(in text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r", with: "\n")
        let pattern = #"(?is)\b(?:credits|créditos)\b[\s\S]{0,220}?(?:US\$\s*|\$\s*|USD\s*)([0-9][0-9.,]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: normalized,
                range: NSRange(normalized.startIndex..., in: normalized)
              ),
              let range = Range(match.range(at: 1), in: normalized)
        else { return nil }
        return decimalAmount(String(normalized[range]))
    }

    nonisolated private static func decimalAmount(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastComma = value.lastIndex(of: ",")
        let lastDot = value.lastIndex(of: ".")
        if let lastComma, let lastDot {
            if lastComma > lastDot {
                return Double(
                    value
                        .replacingOccurrences(of: ".", with: "")
                        .replacingOccurrences(of: ",", with: ".")
                )
            }
            return Double(value.replacingOccurrences(of: ",", with: ""))
        }
        if value.contains(",") {
            return Double(value.replacingOccurrences(of: ",", with: "."))
        }
        return Double(value)
    }
}
#endif
