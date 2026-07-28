import SwiftUI

@main
struct NotchAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(AppEnvironment.shared.store)
                .environment(AppEnvironment.shared.preferences)
                .environment(AppEnvironment.shared.router)
                .environmentObject(AppEnvironment.shared.spending)
        } label: {
            MenuBarLabelView()
                .environment(AppEnvironment.shared.store)
        }
        .menuBarExtraStyle(.window)
    }
}
