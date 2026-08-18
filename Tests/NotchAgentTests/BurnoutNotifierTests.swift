import XCTest
@testable import NotchAgent

final class BurnoutNotifierTests: XCTestCase {
    private final class FakeGate: NotificationGate, @unchecked Sendable {
        var posted: [(String, String)] = []
        func post(title: String, body: String) {
            posted.append((title, body))
        }
    }

    private func signal() -> SessionInsightsPayload.BurnoutSignal {
        .init(title: "CALMA AÍ", detail: "Nesse ritmo você ficará sem token às 15:00.", exhaustsAt: nil)
    }

    // REGRESSÃO: primeiro disparo posta e registra o horário.
    func testFirstFirePosts() {
        let gate = FakeGate()
        let now = Date()
        let fired = BurnoutNotifier.evaluate(signal: signal(), gate: gate, lastNotifiedAt: nil, now: now)
        XCTAssertEqual(fired, now)
        XCTAssertEqual(gate.posted.map(\.0), ["CALMA AÍ"])
    }

    // REGRESSÃO: segundo disparo dentro do cooldown de 6h é bloqueado.
    func testCooldownBlocksSecondFire() {
        let gate = FakeGate()
        let now = Date()
        let last = now.addingTimeInterval(-3600)   // 1h atrás
        let fired = BurnoutNotifier.evaluate(signal: signal(), gate: gate, lastNotifiedAt: last, now: now)
        XCTAssertNil(fired)
        XCTAssertTrue(gate.posted.isEmpty)
    }

    // REGRESSÃO: após o cooldown, dispara de novo.
    func testFireAfterCooldown() {
        let gate = FakeGate()
        let now = Date()
        let last = now.addingTimeInterval(-7 * 3600)  // 7h atrás
        let fired = BurnoutNotifier.evaluate(signal: signal(), gate: gate, lastNotifiedAt: last, now: now)
        XCTAssertEqual(fired, now)
        XCTAssertEqual(gate.posted.count, 1)
    }
}
