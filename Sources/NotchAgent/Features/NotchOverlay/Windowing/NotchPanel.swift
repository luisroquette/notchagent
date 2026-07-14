import AppKit
import SwiftUI

/// Borderless, non-activating floating panel pinned to the top of the screen.
/// It joins all Spaces and stays visible over fullscreen apps.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
    }

    // Needed so controls inside the expanded panel receive clicks.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The window is always sized to the maximum expanded canvas and fully
/// transparent. Without this hit-test override the invisible regions would
/// swallow clicks meant for apps underneath — the single most important
/// detail of a notch overlay.
final class NotchHitTestView: NSHostingView<AnyView> {
    var interactiveRect: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the superview's coordinate space.
        let local = superview.map { convert(point, from: $0) } ?? point
        guard interactiveRect().contains(local) else { return nil }
        return super.hitTest(point)
    }
}
