import XCTest

final class AgentMeterMobileUITests: XCTestCase {
    @MainActor
    func testQuickOnboardingCreatesFirstPlan() throws {
        let app = launch(["-ResetAgentMeterData"])

        let add = app.buttons["home-add-subscription"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()

        let plan = app.textFields["quick-plan-name"]
        XCTAssertTrue(plan.waitForExistence(timeout: 2))
        plan.tap()
        plan.typeText("Pro")

        let price = app.textFields["quick-price"]
        price.tap()
        price.typeText("99.90")
        app.buttons["quick-save"].tap()

        XCTAssertTrue(app.staticTexts["1 PLANO ATIVO"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSeededSubscriptionCanConfirmRenewal() throws {
        let app = launch(["-ResetAgentMeterData", "-SeedPreviewData"])

        let wallet = app.buttons["tab-wallet"]
        XCTAssertTrue(wallet.waitForExistence(timeout: 3))
        wallet.tap()

        let row = app.buttons["subscription-row-claude"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        let confirm = app.buttons["confirm-renewal-claude"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        confirm.tap()
        app.buttons["Confirmar cobrança"].tap()

        XCTAssertTrue(row.exists)
        XCTAssertFalse(confirm.waitForExistence(timeout: 2))
    }

    @MainActor
    func testSeededSubscriptionCanBeDeleted() throws {
        let app = launch(["-ResetAgentMeterData", "-SeedPreviewData"])
        app.buttons["tab-wallet"].tap()

        let row = app.buttons["subscription-row-claude"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.swipeLeft()
        app.buttons["Excluir"].tap()

        XCTAssertFalse(row.waitForExistence(timeout: 2))
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "br.com.lfrprojects.agentmeter.mobile")
        app.launchArguments = arguments
        app.launch()
        return app
    }
}
