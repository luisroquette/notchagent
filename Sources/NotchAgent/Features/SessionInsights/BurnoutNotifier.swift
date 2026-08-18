import Foundation
import UserNotifications

/// Saída de notificação do sinal CALMA AÍ. `evaluate` é puro sobre o gate
/// injetado (testável sem UNUserNotificationCenter); o cooldown de 6h evita
/// fadiga de alerta.
protocol NotificationGate: Sendable {
    func post(title: String, body: String)
}

final class UNNotificationGate: NotificationGate, @unchecked Sendable {
    static let shared = UNNotificationGate()
    private let center = UNUserNotificationCenter.current()

    func requestAuthorizationIfNeeded() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "burnout-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}

enum BurnoutNotifier {
    static let cooldown: TimeInterval = 6 * 3600

    static func shouldFire(lastNotifiedAt: Date?, now: Date = Date(), cooldown: TimeInterval = Self.cooldown) -> Bool {
        guard let lastNotifiedAt else { return true }
        return now.timeIntervalSince(lastNotifiedAt) >= cooldown
    }

    /// Retorna `now` (disparou) quando o cooldown permite; nil quando bloqueado.
    static func evaluate(
        signal: SessionInsightsPayload.BurnoutSignal,
        gate: any NotificationGate,
        lastNotifiedAt: Date?,
        now: Date = Date()
    ) -> Date? {
        guard shouldFire(lastNotifiedAt: lastNotifiedAt, now: now) else { return nil }
        gate.post(title: signal.title, body: signal.detail)
        return now
    }

    static func lastNotifiedKey(for provider: ProviderID) -> String {
        "burnout.lastNotified.\(provider.rawValue)"
    }
}
