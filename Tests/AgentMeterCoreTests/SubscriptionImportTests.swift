import XCTest
@testable import AgentMeterCore

final class SubscriptionImportTests: XCTestCase {
    func testCSVTemplateIsEmptyAndImportable() {
        let preview = SubscriptionImportParser.preview(
            data: SubscriptionImportTemplate.data,
            format: .csv,
            existing: []
        )

        XCTAssertEqual(SubscriptionImportTemplate.filename, "agentmeter-assinaturas.csv")
        XCTAssertTrue(preview.subscriptions.isEmpty)
        XCTAssertTrue(preview.issues.isEmpty)
    }

    func testCSVImportParsesBrazilianPriceAndOptionalFields() {
        let csv = """
        provider,plan,price,cycle,renewal_date,tax,reminder_days
        Claude,Pro,"R$ 99,90",monthly,2026-08-01,10,5
        Gemini,Advanced,1200,yearly,2026-12-01,0,3
        """

        let preview = SubscriptionImportParser.preview(
            data: Data(csv.utf8),
            format: .csv,
            existing: []
        )

        XCTAssertTrue(preview.issues.isEmpty)
        XCTAssertEqual(preview.subscriptions.count, 2)
        XCTAssertEqual(preview.subscriptions[0].basePriceBRL, 99.9)
        XCTAssertEqual(preview.subscriptions[0].taxPercentage, 10)
        XCTAssertEqual(preview.subscriptions[1].billingCycle, .yearly)
    }

    func testInvalidRowsAreReportedWithoutBlockingValidRows() {
        let csv = """
        provider,plan,price,cycle,renewal_date
        Claude,Pro,99,monthly,2026-08-01
        Unknown,Nope,50,monthly,2026-08-01
        ChatGPT,Plus,0,monthly,2026-08-01
        """

        let preview = SubscriptionImportParser.preview(data: Data(csv.utf8), format: .csv, existing: [])

        XCTAssertEqual(preview.subscriptions.count, 1)
        XCTAssertEqual(preview.issues.count, 2)
        XCTAssertEqual(preview.issues.map(\.line), [3, 4])
    }

    func testImportSkipsExistingAndRepeatedPlans() {
        let existing = AISubscription(
            provider: .claude,
            planName: "Pro",
            basePriceBRL: 99,
            nextRenewalDate: .distantFuture
        )
        let csv = """
        provider,plan,price,cycle,renewal_date
        Claude,Pro,99,monthly,2026-08-01
        Gemini,Advanced,100,monthly,2026-08-01
        Gemini,Advanced,100,monthly,2026-08-01
        """

        let preview = SubscriptionImportParser.preview(data: Data(csv.utf8), format: .csv, existing: [existing])

        XCTAssertEqual(preview.subscriptions.map(\.provider), [.gemini])
        XCTAssertEqual(preview.duplicateCount, 2)
    }

    func testJSONImportAcceptsProviderAndPlanAliases() {
        let json = """
        [
          {"provider":"chatgpt","planName":"Plus","price":20,"billingCycle":"monthly","nextRenewalDate":"2026-08-01"}
        ]
        """

        let preview = SubscriptionImportParser.preview(data: Data(json.utf8), format: .json, existing: [])

        XCTAssertTrue(preview.issues.isEmpty)
        XCTAssertEqual(preview.subscriptions.first?.provider, .chatGPT)
        XCTAssertEqual(preview.subscriptions.first?.planName, "Plus")
    }
}
