import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app: menu bar + overlay only, no Dock icon.
        NSApp.setActivationPolicy(.accessory)
        AppEnvironment.shared.bootstrap()
        Log.app.info("application launched")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
