import AppKit
import SwiftUI

/// Owns the overlay panel lifecycle: creation, screen placement, and
/// repositioning on display/space/resolution changes.
@MainActor
final class NotchWindowController {
    private var panel: NotchPanel?
    private let viewModel: NotchViewModel
    private let store: UsageStore
    private let router: WindowRouter
    private var scrollMonitor: Any?
    private var keyMonitor: Any?

    init(viewModel: NotchViewModel, store: UsageStore, router: WindowRouter) {
        self.viewModel = viewModel
        self.store = store
        self.router = router
    }

    func show() {
        rebuild()
        installEventMonitors()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    func hide() {
        viewModel.collapseNow()
        panel?.orderOut(nil)
        panel = nil
    }

    /// Re-evaluates geometry and settings; safe to call at any time.
    func rebuild() {
        let settings = store.settings
        guard settings.notchOverlayEnabled, let screen = NotchGeometry.preferredScreen() else {
            Log.notch.info("overlay disabled or no screen available")
            hide()
            return
        }

        let geometry = NotchGeometry.detect(on: screen)
        if !geometry.hasNotch && !settings.fallbackPillEnabled {
            Log.notch.info("no notch and fallback pill disabled — menu bar only mode")
            hide()
            return
        }
        viewModel.geometry = geometry

        let frame = NotchGeometry.panelFrame(canvas: NotchViewModel.canvasSize, screenFrame: geometry.screenFrame)
        defer { panel?.appearance = settings.themeMode.nsAppearance }
        if panel == nil {
            let newPanel = NotchPanel(contentRect: frame)
            let root = AnyView(
                NotchContainerView()
                    .environment(viewModel)
                    .environment(store)
                    .environment(store.preferences)
                    .environment(router)
            )
            let hosting = NotchHitTestView(rootView: root)
            hosting.interactiveRect = { [weak viewModel] in
                viewModel?.interactiveRect ?? .zero
            }
            newPanel.contentView = hosting
            panel = newPanel
            Log.notch.info("overlay panel created")
        }
        panel?.setFrame(frame, display: true)
        panel?.orderFrontRegardless()
    }

    func applyAppearance(_ appearance: NSAppearance?) {
        panel?.appearance = appearance
    }

    /// Trackpad paging + Escape-to-collapse, scoped to our panel only.
    private func installEventMonitors() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            // Natural scrolling: swiping left advances, like flipping a page.
            self.viewModel.handleScroll(
                deltaX: event.scrollingDeltaX,
                phase: event.phase,
                momentumPhase: event.momentumPhase
            )
            return event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            // Scoped to the panel: Escape typed into Settings/Dashboard must
            // reach those windows, not collapse the notch (review finding).
            guard let self, event.keyCode == 53,
                  let panel = self.panel, event.window === panel,
                  self.viewModel.isExpanded
            else { return event }
            self.viewModel.collapseNow()
            return nil
        }
    }

    @objc private func screenParametersChanged() {
        Log.notch.info("screen parameters changed — repositioning overlay")
        rebuild()
    }

    @objc private func spaceChanged() {
        panel?.orderFrontRegardless()
    }
}
