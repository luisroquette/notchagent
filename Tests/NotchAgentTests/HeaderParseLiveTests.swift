import XCTest
@testable import NotchAgent

final class HeaderParseLiveTests: XCTestCase {
    func testParseRealHeaders() {
        let headers: [String: String] = [
            "anthropic-ratelimit-unified-status": "rejected",
            "anthropic-ratelimit-unified-5h-utilization": "0.0",
            "anthropic-ratelimit-unified-5h-reset": "1787198400",
            "anthropic-ratelimit-unified-7d-utilization": "1.0",
            "anthropic-ratelimit-unified-7d-reset": "1787331600",
            "anthropic-ratelimit-unified-7d-surpassed-threshold": "1.0",
        ]
        let quota = ClaudeQuotaProbe.parse(headers: headers)
        print("sessionPercent:", quota.sessionPercent as Any)
        print("weeklyPercent:", quota.weeklyPercent as Any)
        print("weeklyResetsAt:", quota.weeklyResetsAt as Any)
        print("status:", quota.status as Any)
        XCTAssertNotNil(quota.weeklyPercent)
    }
}
