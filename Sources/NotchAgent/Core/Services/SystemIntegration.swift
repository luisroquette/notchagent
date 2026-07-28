import AppKit
import ServiceManagement
import UserNotifications
import AgentMeterCore

/// Both integrations below require a real .app bundle (see Scripts/make-app.sh).
/// When running unbundled (`swift run`), they report unavailable and the UI
/// explains why instead of failing.
@MainActor
enum BundleContext {
    static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }
}

/// Launch-at-login via SMAppService (macOS 13+).
@MainActor
enum LoginItem {
    static var isAvailable: Bool { BundleContext.isBundledApp }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.app.info("launch at login \(enabled ? "enabled" : "disabled", privacy: .public)")
        } catch {
            Log.app.error("launch at login failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// System notifications for warning/critical transitions. All UNUserNotification
/// calls stay behind the bundle guard — touching the center unbundled crashes.
@MainActor
final class NotificationService {
    private var authorizationRequested = false

    static var isAvailable: Bool { BundleContext.isBundledApp }

    func post(_ alert: ProviderAlert, settings: AppSettings) {
        guard Self.isAvailable, settings.notificationsEnabled, alert.level > .normal else { return }
        let center = UNUserNotificationCenter.current()

        if !authorizationRequested {
            authorizationRequested = true
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                Log.app.info("notification authorization: \(granted, privacy: .public)")
            }
        }

        let content = UNMutableNotificationContent()
        content.title = alert.level == .critical ? "Quota critical" : "Quota warning"
        content.body = alert.message
        if alert.level == .critical {
            content.sound = .default
        }
        center.add(UNNotificationRequest(
            identifier: "quota-\(alert.provider.rawValue)-\(alert.level.rawValue)",
            content: content,
            trigger: nil
        ))
    }

    func postRestored(_ moment: RestoreMoment, settings: AppSettings) {
        guard Self.isAvailable, settings.notificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "Session restored"
        content.body = moment.message
        content.sound = .default
        center.add(UNNotificationRequest(
            identifier: "restore-\(moment.provider.rawValue)-\(Int(moment.firedAt.timeIntervalSince1970))",
            content: content,
            trigger: nil
        ))
    }

    func postBudget(_ alert: MonthlyBudgetAlert, settings: AppSettings) {
        guard Self.isAvailable, settings.notificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = alert.level == .exceeded ? "Orçamento excedido" : "Orçamento de IA em risco"
        content.body = "Previsão mensal em \(Int(alert.percent.rounded()))% do orçamento."
        if alert.level == .critical || alert.level == .exceeded { content.sound = .default }
        center.add(UNNotificationRequest(
            identifier: "budget-\(alert.level.rawValue)-\(Calendar.current.component(.month, from: .now))",
            content: content,
            trigger: nil
        ))
    }
}
