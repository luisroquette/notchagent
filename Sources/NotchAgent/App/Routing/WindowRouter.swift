import AppKit
import Observation
import SwiftUI

/// AppKit-managed windows for Dashboard and Settings. Scene-based windows are
/// unreliable to open from an overlay panel context, so routing is explicit.
@MainActor
@Observable
final class WindowRouter {
    @ObservationIgnored weak var environment: AppEnvironment?

    @ObservationIgnored private var dashboardWindow: NSWindow?
    @ObservationIgnored private var settingsWindow: NSWindow?

    func openDashboard() {
        guard let environment else { return }
        if dashboardWindow == nil {
            let view = DashboardView()
                .environment(environment.store)
                .environment(environment.preferences)
                .environment(self)
            dashboardWindow = makeWindow(
                title: "NotchAgent — Dashboard",
                content: AnyView(view),
                size: NSSize(width: 860, height: 620)
            )
        }
        present(dashboardWindow)
    }

    func openSettings() {
        guard let environment else { return }
        if settingsWindow == nil {
            let view = SettingsView()
                .environment(environment.store)
                .environment(environment.preferences)
            settingsWindow = makeWindow(
                title: "NotchAgent — Settings",
                content: AnyView(view),
                size: NSSize(width: 480, height: 560)
            )
        }
        present(settingsWindow)
    }

    func applyAppearance(_ appearance: NSAppearance?) {
        dashboardWindow?.appearance = appearance
        settingsWindow?.appearance = appearance
    }

    private func makeWindow(title: String, content: AnyView, size: NSSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.appearance = environment?.preferences.settings.themeMode.nsAppearance
        window.contentViewController = NSHostingController(rootView: content)
        window.setContentSize(size)
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
