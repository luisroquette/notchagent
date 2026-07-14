import AppKit
import Foundation
import Observation
import SwiftUI

/// UI state for the notch overlay: compact/expanded mode, hover debouncing,
/// pinning, pager state, and the geometry-derived sizes the views and
/// hit-testing share.
@MainActor
@Observable
final class NotchViewModel {
    enum Mode: Equatable {
        case compact
        case expanded
    }

    /// Fixed transparent canvas; content only ever occupies part of it.
    static let canvasSize = CGSize(width: 720, height: 460)

    private(set) var mode: Mode = .compact
    var isPinned = false
    var geometry: NotchGeometry
    static let pageCount = 5

    /// Current page of the expanded pager
    /// (0 Now, 1 Burn, 2 Rhythm, 3 Claude Models, 4 OpenAI Models).
    /// Persists across hover-expands so users return to where they were.
    var expandedPage: Int = 0
    /// Which edge the incoming page slides from (drives the transition).
    var pageDirection: Edge = .trailing
    /// Provider highlighted on the Burn page.
    var focusProvider: ProviderID = .claudeCode

    private let wingWidth: CGFloat = 150
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var scrollAccumulator: CGFloat = 0
    @ObservationIgnored private var lastScrollAt = Date.distantPast
    @ObservationIgnored private var scrollLocked = false

    init(geometry: NotchGeometry = NotchGeometry(hasNotch: false, notchWidth: 0, topInset: 24, screenFrame: .zero)) {
        self.geometry = geometry
    }

    var isExpanded: Bool { mode == .expanded }

    /// Vertical offset from the top of the canvas. With a notch the shape hugs
    /// the screen edge; without one, the fallback pill sits below the menu bar.
    var topOffset: CGFloat { geometry.hasNotch ? 0 : geometry.topInset + 6 }

    var compactSize: CGSize {
        geometry.hasNotch
            ? CGSize(width: geometry.notchWidth + wingWidth * 2, height: geometry.topInset)
            : CGSize(width: 320, height: 34)
    }

    var expandedSize: CGSize {
        CGSize(width: 660, height: geometry.hasNotch ? 430 : 410)
    }

    var currentSize: CGSize { isExpanded ? expandedSize : compactSize }

    /// Clickable/hoverable region in view coordinates (origin top-left,
    /// matching the flipped hosting view). Everything outside is click-through.
    var interactiveRect: CGRect {
        let size = currentSize
        return CGRect(
            x: (Self.canvasSize.width - size.width) / 2,
            y: topOffset,
            width: size.width,
            height: size.height
        )
    }

    func hoverChanged(_ hovering: Bool) {
        hoverTask?.cancel()
        if hovering {
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                self?.mode = .expanded
            }
        } else {
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, let self, !self.isPinned else { return }
                self.mode = .compact
            }
        }
    }

    func togglePin() {
        isPinned.toggle()
        if isPinned {
            mode = .expanded
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func forceExpand() {
        hoverTask?.cancel()
        mode = .expanded
    }

    func collapseNow() {
        isPinned = false
        mode = .compact
    }

    // MARK: Pager

    func goToPage(_ page: Int) {
        let clamped = min(max(page, 0), Self.pageCount - 1)
        guard clamped != expandedPage else { return }
        pageDirection = clamped > expandedPage ? .trailing : .leading
        withAnimation(.spring(duration: 0.32, bounce: 0.14)) {
            expandedPage = clamped
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Two-finger horizontal trackpad scroll flips pages, Apple-style:
    /// exactly ONE page per gesture. After a flip the gesture locks so
    /// momentum events can't stack extra flips; a new gesture (phase .began)
    /// or a real pause unlocks. Plain scroll wheels (no phases) rely on the
    /// pause-based unlock.
    func handleScroll(deltaX: CGFloat, phase: NSEvent.Phase, momentumPhase: NSEvent.Phase) {
        guard isExpanded else { return }
        let now = Date()

        let isNewGesture = phase.contains(.began)
        let isIdleGap = now.timeIntervalSince(lastScrollAt) > 0.5 && momentumPhase.isEmpty
        if isNewGesture || isIdleGap {
            scrollAccumulator = 0
            scrollLocked = false
        }
        lastScrollAt = now

        guard !scrollLocked else { return }
        scrollAccumulator += deltaX

        let step: CGFloat = 55
        if scrollAccumulator <= -step {
            scrollLocked = true
            scrollAccumulator = 0
            goToPage(expandedPage + 1)
        } else if scrollAccumulator >= step {
            scrollLocked = true
            scrollAccumulator = 0
            goToPage(expandedPage - 1)
        }
    }
}
