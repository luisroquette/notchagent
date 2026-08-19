import XCTest
@testable import NotchAgent

/// REGRESSÃO: o painel sumia durante sessões de verificação visual —
/// Esc, botão de fechar e hover-out recolhiam um painel que o
/// --debug-expand acabara de pinar. No modo debug, NADA recolhe.
@MainActor
final class NotchViewModelDebugTests: XCTestCase {
    func testDebugNeverCollapseBlocksCollapseNow() {
        let vm = NotchViewModel()
        vm.modeIsExpandedForTest()
        vm.debugNeverCollapse = true
        vm.collapseNow()
        XCTAssertTrue(vm.isExpanded, "debug mode must never collapse the panel")
    }

    func testDebugNeverCollapseBlocksEscape() {
        let vm = NotchViewModel()
        vm.modeIsExpandedForTest()
        vm.debugNeverCollapse = true
        XCTAssertTrue(vm.handleEscape(), "escape still reports handling")
        XCTAssertTrue(vm.isExpanded, "escape must not collapse in debug mode")
    }

    func testNormalModeStillCollapses() {
        let vm = NotchViewModel()
        vm.modeIsExpandedForTest()
        vm.collapseNow()
        XCTAssertFalse(vm.isExpanded, "normal mode keeps its collapse behavior")
    }
}

private extension NotchViewModel {
    /// Drives the view model to the expanded mode without going through
    /// the hover machinery (tests only).
    func modeIsExpandedForTest() {
        forceExpand()
    }
}
