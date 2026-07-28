import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app: menu bar + overlay only, no Dock icon.
        NSApp.setActivationPolicy(.accessory)
        let arguments = ProcessInfo.processInfo.arguments
        let claudeBillingDiagnostic = arguments.contains("--debug-claude-billing")
        AppEnvironment.shared.bootstrap(startScheduler: !claudeBillingDiagnostic)
        if claudeBillingDiagnostic,
           let account = AppEnvironment.shared.preferences.settings.apiAccounts.first(where: {
               $0.service == .anthropicConsole
           }) {
            Task { @MainActor in
                let quota = await AnthropicConsoleReader(accountID: account.id).fetchQuota()
                Log.providers.info(
                    "claude billing diagnostic success=\(quota != nil, privacy: .public) planBRL=\(quota?.monthlyPlanBRL != nil, privacy: .public) balanceBRL=\(quota?.balanceBRL != nil, privacy: .public)"
                )
            }
        }
        if arguments.contains("--open-settings") {
            DispatchQueue.main.async {
                AppEnvironment.shared.router.openSettings()
            }
        }
        if arguments.contains("--open-api-dashboard") {
            DispatchQueue.main.async {
                AppEnvironment.shared.notchViewModel.expandedPage = 5
                AppEnvironment.shared.notchViewModel.forceExpand()
                AppEnvironment.shared.scheduler.refreshNow()
            }
        }
        Log.app.info("application launched")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
