import XCTest
@testable import NotchAgent

final class BurnoutAlerterTests: XCTestCase {
    private func samples(_ pairs: [(minutesAgo: Double, percent: Double)], now: Date) -> [PercentSample] {
        pairs.map { PercentSample(date: now.addingTimeInterval(-$0.minutesAgo * 60), percent: $0.percent) }
    }

    // REGRESSÃO: ritmo que esgota dentro do lead (≤30min) ANTES do reset vira
    // sinal CALMA AÍ com hora formatada pt_BR.
    func testExhaustionWithinLeadBeforeResetFires() {
        let now = Date()
        // 40% → 80% em 1h = 40%/h → esgota em 30 min exatos
        let signal = BurnoutAlerter.signal(
            samples: samples([(60, 40), (0, 80)], now: now),
            resetsAt: now.addingTimeInterval(4 * 3600), now: now)
        XCTAssertNotNil(signal)
        XCTAssertEqual(signal?.title, "CALMA AÍ")
        XCTAssertTrue(signal?.detail.contains("às") == true)
        XCTAssertNotNil(signal?.exhaustsAt)
    }

    // REGRESSÃO: ritmo plano não dispara.
    func testFlatRateDoesNotFire() {
        let now = Date()
        let signal = BurnoutAlerter.signal(
            samples: samples([(60, 50), (0, 50)], now: now),
            resetsAt: now.addingTimeInterval(4 * 3600), now: now)
        XCTAssertNil(signal)
    }

    // REGRESSÃO: esgotamento DEPOIS do reset não dispara (o reset salva antes).
    func testExhaustionAfterResetDoesNotFire() {
        let now = Date()
        // 40%/h → esgota em 30 min; reset em 20 min chega primeiro
        let signal = BurnoutAlerter.signal(
            samples: samples([(60, 40), (0, 80)], now: now),
            resetsAt: now.addingTimeInterval(20 * 60), now: now)
        XCTAssertNil(signal)
    }

    // REGRESSÃO: sem samples suficientes não dispara.
    func testTooFewSamplesDoesNotFire() {
        let now = Date()
        let signal = BurnoutAlerter.signal(
            samples: [PercentSample(date: now, percent: 70)],
            resetsAt: now.addingTimeInterval(4 * 3600), now: now)
        XCTAssertNil(signal)
    }
}
