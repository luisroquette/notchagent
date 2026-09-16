import XCTest
@testable import NotchAgent

final class ResetCreditNotifierTests: XCTestCase {
    private final class FakeGate: NotificationGate, @unchecked Sendable {
        var posted: [(String, String)] = []
        func post(title: String, body: String) {
            posted.append((title, body))
        }
    }

    private func signal() -> ResetCreditAlerter.Signal {
        .init(title: "RESET GRÁTIS DO CODEX EXPIRANDO", detail: "Você tem 3 redefinição(ões)...")
    }

    // REGRESSÃO: primeiro disparo posta e registra o horário.
    func testFirstFirePosts() {
        let gate = FakeGate()
        let now = Date()
        let fired = ResetCreditNotifier.evaluate(signal: signal(), gate: gate, lastNotifiedAt: nil, now: now)
        XCTAssertEqual(fired, now)
        XCTAssertEqual(gate.posted.count, 1)
    }

    // REGRESSÃO: segundo disparo dentro do cooldown de 24h é bloqueado.
    func testCooldownBlocksSecondFire() {
        let gate = FakeGate()
        let now = Date()
        let last = now.addingTimeInterval(-3600)
        let fired = ResetCreditNotifier.evaluate(signal: signal(), gate: gate, lastNotifiedAt: last, now: now)
        XCTAssertNil(fired)
        XCTAssertTrue(gate.posted.isEmpty)
    }

    // REGRESSÃO: após o cooldown, dispara de novo.
    func testFireAfterCooldown() {
        let gate = FakeGate()
        let now = Date()
        let last = now.addingTimeInterval(-25 * 3600)
        let fired = ResetCreditNotifier.evaluate(signal: signal(), gate: gate, lastNotifiedAt: last, now: now)
        XCTAssertEqual(fired, now)
        XCTAssertEqual(gate.posted.count, 1)
    }
}
