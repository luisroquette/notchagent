import XCTest
@testable import NotchAgent

final class NotchExpandedViewTests: XCTestCase {
    func testPanelStripProvidersExcludesGemini() {
        // Gemini CLI strip removed from the panel — unused, "NOT INSTALLED"
        // noise. The provider keeps working internally (settings, snapshots).
        XCTAssertFalse(NotchExpandedView.panelStripProviders.contains(.geminiCLI))
    }

    func testPanelStripProvidersKeepsOtherStrips() {
        XCTAssertTrue(NotchExpandedView.panelStripProviders.contains(.apiAccounts))
    }

    func testPanelCardProvidersAreClaudeAndCodex() {
        XCTAssertEqual(NotchExpandedView.panelCardProviders, [.claudeCode, .codex])
    }
}
