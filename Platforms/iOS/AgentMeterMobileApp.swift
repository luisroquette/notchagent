import AgentMeterCore
import SwiftUI

@main
struct AgentMeterMobileApp: App {
    @StateObject private var subscriptions: SubscriptionStore

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ResetAgentMeterData") {
            let defaults = UserDefaults.standard
            for suffix in ["", ".tombstones", ".history", ".icloud-enabled"] {
                defaults.removeObject(forKey: "agentmeter.subscriptions.v1\(suffix)")
            }
        }

        let store = SubscriptionStore()
        if arguments.contains("-SeedPreviewData"), store.subscriptions.isEmpty {
            store.add(AISubscription(provider: .claude, planName: "Max", basePriceBRL: 100, billingCycle: .monthly, nextRenewalDate: Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now))
            store.add(AISubscription(provider: .chatGPT, planName: "Plus", basePriceBRL: 20, taxPercentage: 5, billingCycle: .monthly, nextRenewalDate: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now))
        }
        _subscriptions = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environmentObject(subscriptions)
        }
    }
}
