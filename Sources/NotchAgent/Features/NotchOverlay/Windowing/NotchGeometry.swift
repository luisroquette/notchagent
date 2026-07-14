import AppKit

/// There is no official notch API on macOS. Detection combines
/// `safeAreaInsets.top` (> 0 means a camera housing exists) with the
/// auxiliary top areas (macOS 12+) to compute the exact notch width.
/// Everything downstream treats this as *inferred* geometry with a fallback.
struct NotchGeometry: Equatable, Sendable {
    var hasNotch: Bool
    var notchWidth: CGFloat
    /// Height of the top strip (menu bar / camera housing) in points.
    var topInset: CGFloat
    var screenFrame: CGRect

    @MainActor
    static func detect(on screen: NSScreen) -> NotchGeometry {
        let inset = screen.safeAreaInsets.top
        if inset > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchWidth = screen.frame.width - left.width - right.width
            if notchWidth > 0 {
                Log.notch.info("notch detected: width \(notchWidth, privacy: .public)pt, inset \(inset, privacy: .public)pt")
                return NotchGeometry(hasNotch: true, notchWidth: notchWidth, topInset: inset, screenFrame: screen.frame)
            }
        }
        Log.notch.info("no notch on screen — using fallback pill geometry")
        return NotchGeometry(
            hasNotch: false,
            notchWidth: 0,
            topInset: NSStatusBar.system.thickness,
            screenFrame: screen.frame
        )
    }

    /// Prefers the built-in display with a notch; falls back to the main screen.
    @MainActor
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Pure and testable: top-centered window frame in screen coordinates
    /// (AppKit origin is bottom-left).
    static func panelFrame(canvas: CGSize, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: (screenFrame.midX - canvas.width / 2).rounded(),
            y: screenFrame.maxY - canvas.height,
            width: canvas.width,
            height: canvas.height
        )
    }
}
