import AppKit
import XCTest
@testable import NotchAgent

/// REGRESSÃO: um swipe lateral pulava da primeira à última página porque os
/// eventos de momentum continuavam acumulando flips após o primeiro.
@MainActor
final class ScrollPagingTests: XCTestCase {
    private func makeViewModel() -> NotchViewModel {
        let vm = NotchViewModel(geometry: NotchGeometry(
            hasNotch: true, notchWidth: 200, topInset: 38,
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
        ))
        vm.forceExpand()
        return vm
    }

    /// Gesto completo: began + drags + longa cauda de momentum → UMA página.
    func testOneGestureWithMomentumFlipsExactlyOnePage() {
        let vm = makeViewModel()
        vm.handleScroll(deltaX: -20, phase: .began, momentumPhase: [])
        for _ in 0..<30 {
            vm.handleScroll(deltaX: -25, phase: .changed, momentumPhase: [])
        }
        vm.handleScroll(deltaX: 0, phase: .ended, momentumPhase: [])
        for _ in 0..<40 {
            vm.handleScroll(deltaX: -30, phase: [], momentumPhase: .changed)
        }
        XCTAssertEqual(vm.expandedPage, 1, "momentum must not stack extra page flips")
    }

    func testSecondGestureFlipsAgain() {
        let vm = makeViewModel()
        vm.handleScroll(deltaX: -60, phase: .began, momentumPhase: [])
        XCTAssertEqual(vm.expandedPage, 1)
        // Novo gesto físico destrava e avança mais uma.
        vm.handleScroll(deltaX: -60, phase: .began, momentumPhase: [])
        XCTAssertEqual(vm.expandedPage, 2)
    }

    func testReverseDirectionAndClamping() {
        let vm = makeViewModel()
        vm.handleScroll(deltaX: 80, phase: .began, momentumPhase: [])
        XCTAssertEqual(vm.expandedPage, 0, "clamped at the first page")
        vm.handleScroll(deltaX: -80, phase: .began, momentumPhase: [])
        vm.handleScroll(deltaX: 80, phase: .began, momentumPhase: [])
        XCTAssertEqual(vm.expandedPage, 0, "swiping back returns")
    }

    func testIgnoredWhenCompact() {
        let vm = makeViewModel()
        vm.collapseNow()
        vm.handleScroll(deltaX: -200, phase: .began, momentumPhase: [])
        XCTAssertEqual(vm.expandedPage, 0)
    }
}
