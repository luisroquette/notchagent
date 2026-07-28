import AgentMeterCore
import UserNotifications

enum RenewalNotificationScheduler {
    static func requestAuthorizationAndSchedule(_ subscriptions: [AISubscription]) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard granted else { return false }
        await scheduleAll(subscriptions)
        return true
    }

    static func scheduleAll(_ subscriptions: [AISubscription]) async {
        for subscription in subscriptions where subscription.isActive {
            await schedule(subscription)
        }
    }

    static func schedule(_ subscription: AISubscription) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        center.removePendingNotificationRequests(withIdentifiers: [identifier(subscription.id)])
        guard subscription.isActive,
              let alertDay = Calendar.current.date(
                byAdding: .day,
                value: -subscription.reminderDaysBefore,
                to: subscription.nextRenewalDate
              ) else { return }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: alertDay)
        components.hour = 9
        guard let alertDate = Calendar.current.date(from: components) else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Assinatura próxima da renovação")
        let bodyFormat = String(localized: "%@ · %@ será renovado em %@.")
        content.body = String(
            format: bodyFormat,
            locale: .current,
            subscription.provider.displayName,
            subscription.planName,
            subscription.nextRenewalDate.formatted(date: .abbreviated, time: .omitted)
        )
        content.sound = .default

        let trigger: UNNotificationTrigger
        if alertDate > .now {
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            // Alertas ativados depois do prazo ainda precisam aparecer uma vez,
            // em vez de desaparecerem até o próximo ciclo.
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        }
        let request = UNNotificationRequest(
            identifier: identifier(subscription.id),
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    static func cancel(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(id)])
    }

    static func isAuthorized() async -> Bool {
        await authorizationStatus() == .authorized
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private static func identifier(_ id: UUID) -> String {
        "agentmeter.renewal.\(id.uuidString)"
    }
}
