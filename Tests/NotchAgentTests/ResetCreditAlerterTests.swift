import XCTest
@testable import NotchAgent

final class ResetCreditAlerterTests: XCTestCase {
    // REGRESSÃO: crédito expirando dentro do lead (≤72h) dispara sinal.
    func testExpiringWithinLeadFires() {
        let now = Date()
        let signal = ResetCreditAlerter.signal(
            credits: RateLimitResetCredits(availableCount: 3, totalCount: 3, soonestExpiresAt: now.addingTimeInterval(48 * 3600)),
            now: now
        )
        XCTAssertNotNil(signal)
        XCTAssertTrue(signal?.detail.contains("3") == true)
    }

    // REGRESSÃO: crédito expirando fora do lead (>72h) não dispara.
    func testExpiringOutsideLeadDoesNotFire() {
        let now = Date()
        let signal = ResetCreditAlerter.signal(
            credits: RateLimitResetCredits(availableCount: 3, totalCount: 3, soonestExpiresAt: now.addingTimeInterval(10 * 24 * 3600)),
            now: now
        )
        XCTAssertNil(signal)
    }

    // REGRESSÃO: sem créditos disponíveis não dispara, mesmo com expiresAt presente.
    func testZeroAvailableDoesNotFire() {
        let now = Date()
        let signal = ResetCreditAlerter.signal(
            credits: RateLimitResetCredits(availableCount: 0, totalCount: 3, soonestExpiresAt: now.addingTimeInterval(3600)),
            now: now
        )
        XCTAssertNil(signal)
    }

    // REGRESSÃO: crédito já expirado (no passado) não dispara.
    func testAlreadyExpiredDoesNotFire() {
        let now = Date()
        let signal = ResetCreditAlerter.signal(
            credits: RateLimitResetCredits(availableCount: 3, totalCount: 3, soonestExpiresAt: now.addingTimeInterval(-3600)),
            now: now
        )
        XCTAssertNil(signal)
    }

    func testNilCreditsDoesNotFire() {
        XCTAssertNil(ResetCreditAlerter.signal(credits: nil))
    }
}
