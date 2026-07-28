import AgentMeterCore
import SwiftUI

@main
struct AgentMeterWatchApp: App {
    @StateObject private var subscriptions = SubscriptionStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(subscriptions)
        }
    }
}
