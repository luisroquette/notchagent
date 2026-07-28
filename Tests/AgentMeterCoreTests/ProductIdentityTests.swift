import XCTest
@testable import AgentMeterCore

final class ProductIdentityTests: XCTestCase {
    func testProductFamilyNames() {
        XCTAssertEqual(AgentMeterProduct.mobileName, "AgentMeter: AI Control")
        XCTAssertEqual(AgentMeterProduct.macName, "AgentMeter: NotchAgent")
        XCTAssertEqual(AgentMeterProduct.windowsName, "AgentMeter: Desktop Bar")
    }

    func testConfidenceIsClamped() {
        XCTAssertEqual(MetricProvenance(source: .manual, capturedAt: .distantPast, confidence: -1).confidence, 0)
        XCTAssertEqual(MetricProvenance(source: .macSync, capturedAt: .distantPast, confidence: 2).confidence, 1)
    }
}
