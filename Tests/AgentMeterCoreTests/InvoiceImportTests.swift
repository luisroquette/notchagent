import XCTest
@testable import AgentMeterCore

final class InvoiceImportTests: XCTestCase {
    func testImportsOfficialInvoiceRows() {
        let data = Data("date,provider,amount_brl,description\n2026-07-18,claude,42.50,API\n".utf8)
        let preview = InvoiceImportParser.preview(data: data)
        XCTAssertTrue(preview.issues.isEmpty)
        XCTAssertEqual(preview.expenses.count, 1)
        XCTAssertEqual(preview.expenses.first?.amountBRL, 42.5)
        XCTAssertEqual(preview.expenses.first?.source, .officialInvoice)
    }
}
