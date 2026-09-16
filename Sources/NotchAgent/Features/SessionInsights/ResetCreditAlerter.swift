import Foundation

/// Codex's free "Full reset" credits expire on their own schedule — warn
/// before one lapses unused. Pure — credits and now go in, a signal comes out.
enum ResetCreditAlerter {
    static let leadHours: TimeInterval = 72

    struct Signal: Equatable {
        var title: String
        var detail: String
    }

    static func signal(credits: RateLimitResetCredits?, now: Date = Date()) -> Signal? {
        guard let credits, credits.availableCount > 0,
              let expiresAt = credits.soonestExpiresAt,
              expiresAt > now,
              expiresAt.timeIntervalSince(now) <= leadHours * 3600 else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "dd/MM 'às' HH:mm"
        return Signal(
            title: "RESET GRÁTIS DO CODEX EXPIRANDO",
            detail: "Você tem \(credits.availableCount) redefinição(ões) de limite — a mais próxima expira em \(formatter.string(from: expiresAt))."
        )
    }
}
