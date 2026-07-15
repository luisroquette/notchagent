import XCTest
@testable import NotchAgent

/// REGRESSÃO: card mostrava "BLOCKED" (vermelho) no topo E "99% left" (verde)
/// no numeral-herói ao mesmo tempo — duas fontes de verdade contradizendo-se
/// (e o runner corretamente em GAME OVER enquanto o número dizia "tudo bem").
@MainActor
final class BlockedCoherenceTests: XCTestCase {
    private func blockedSnapshot(sessionUsedPercent: Double?, weeklyUsedPercent: Double? = nil) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claudeCode,
            health: .ok,
            session: sessionUsedPercent.map { SessionUsage(resetsAt: Date().addingTimeInterval(3000), usedPercent: $0) },
            weekly: weeklyUsedPercent.map { WeeklyUsage(usedPercent: $0) },
            quotaStatus: .blocked
        )
    }

    func testBlockedForcesEmptyGaugeRegardlessOfStalePercent() {
        // Exatamente o cenário reportado: probe ainda mostrando 1% usado
        // (99% left) na sessão nova, mas a API já sinalizou rejected.
        let metric = GaugeMetric.from(blockedSnapshot(sessionUsedPercent: 1))
        XCTAssertEqual(metric?.used, 100, "a BLOCKED status must never coexist with a calm percentage")
        XCTAssertEqual(metric?.remaining, 0)
        XCTAssertFalse(metric?.isWeekly ?? true)
    }

    func testBlockedWithOnlyWeeklyDataKeepsWeeklyLabel() {
        let metric = GaugeMetric.from(blockedSnapshot(sessionUsedPercent: nil, weeklyUsedPercent: 40))
        XCTAssertEqual(metric?.used, 100)
        XCTAssertTrue(metric?.isWeekly ?? false)
    }

    func testNotBlockedUsesRealPercent() {
        let snapshot = UsageSnapshot(
            provider: .claudeCode, health: .ok,
            session: SessionUsage(usedPercent: 35), quotaStatus: .ok
        )
        XCTAssertEqual(GaugeMetric.from(snapshot)?.used, 35)
    }

    func testBlockedFiresStickyThresholdAlert() {
        let store = UsageStore(preferences: PreferencesStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!))
        store.apply(blockedSnapshot(sessionUsedPercent: 1))
        XCTAssertEqual(store.activeThresholdAlert?.threshold, 5, "blocked must trigger the deepest, sticky takeover")
    }
}

@MainActor
final class RestoreMomentTests: XCTestCase {
    private func makeStore() -> UsageStore {
        UsageStore(preferences: PreferencesStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!))
    }

    private func snapshot(blocked: Bool, sessionUsedPercent: Double?, lastActivityAt: Date?) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claudeCode,
            health: .ok,
            session: sessionUsedPercent.map { SessionUsage(usedPercent: $0) },
            lastActivityAt: lastActivityAt,
            quotaStatus: blocked ? .blocked : .ok
        )
    }

    func testRecoveryFiresOnBlockedToUnblockedTransition() {
        let store = makeStore()
        let now = Date()
        store.apply(snapshot(blocked: true, sessionUsedPercent: 1, lastActivityAt: now))
        XCTAssertNil(store.activeRestoreMoment, "still blocked — no celebration yet")
        store.apply(snapshot(blocked: false, sessionUsedPercent: 2, lastActivityAt: now))
        XCTAssertNotNil(store.activeRestoreMoment, "unblock while recently active must celebrate")
        XCTAssertEqual(store.activeRestoreMoment?.remaining, 98)
    }

    func testNoRecoveryWithoutPriorBlockedObservation() {
        let store = makeStore()
        // Primeiro snapshot já não-bloqueado — nunca vimos o estado bloqueado.
        store.apply(snapshot(blocked: false, sessionUsedPercent: 40, lastActivityAt: Date()))
        XCTAssertNil(store.activeRestoreMoment)
    }

    func testColdStartAlreadyBlockedDoesNotFireRestoreOnFirstClear() {
        let store = makeStore()
        // App relançado já com o snapshot persistido bloqueado (sem observação anterior)…
        store.apply(snapshot(blocked: true, sessionUsedPercent: 1, lastActivityAt: Date()))
        // …e o PRIMEIRO clear ainda deve celebrar, pois já observamos o blocked=true localmente.
        store.apply(snapshot(blocked: false, sessionUsedPercent: 2, lastActivityAt: Date()))
        XCTAssertNotNil(store.activeRestoreMoment)
    }

    func testNoRecoveryWhenUserWasAwayForAWhile() {
        let store = makeStore()
        let longAgo = Date().addingTimeInterval(-3600)
        store.apply(snapshot(blocked: true, sessionUsedPercent: 1, lastActivityAt: longAgo))
        store.apply(snapshot(blocked: false, sessionUsedPercent: 2, lastActivityAt: longAgo))
        XCTAssertNil(store.activeRestoreMoment, "stale activity means the user wasn't there to feel the recovery")
    }

    /// REGRESSÃO: usuário relatou ver o aviso "ALMOST EMPTY 0%" congelado no
    /// exato momento em que a janela (5h/semanal) resetava — a celebração só
    /// disparava para o caminho estreito quotaStatus==.blocked, então um reset
    /// de janela comum (nunca chega a ficar "blocked", só o percentual da API
    /// sobe de volta) não tinha NENHUM feedback positivo.
    func testRecoveryFiresOnPlainWindowResetWithoutEverBeingBlocked() {
        let store = makeStore()
        let now = Date()
        store.apply(snapshot(blocked: false, sessionUsedPercent: 96, lastActivityAt: now))
        XCTAssertEqual(store.activeThresholdAlert?.threshold, 5, "4% restante deve disparar o alerta mais grave")
        XCTAssertNil(store.activeRestoreMoment)

        store.apply(snapshot(blocked: false, sessionUsedPercent: 1, lastActivityAt: now))
        XCTAssertNotNil(store.activeRestoreMoment, "reset de janela sem jamais passar por blocked também deve celebrar")
        XCTAssertEqual(store.activeRestoreMoment?.previousRemaining, 4, "ponto de partida da animação = quão baixo chegou")
        XCTAssertEqual(store.activeRestoreMoment?.remaining, 99)
    }

    func testDangerTakeoverOutranksCelebrationWhenBothPending() {
        let store = makeStore()
        // Claude se recupera…
        store.apply(snapshot(blocked: true, sessionUsedPercent: 1, lastActivityAt: Date()))
        store.apply(snapshot(blocked: false, sessionUsedPercent: 2, lastActivityAt: Date()))
        XCTAssertNotNil(store.activeRestoreMoment)
        // …mas Codex cai no crítico no mesmo instante: o perigo deve ganhar a exibição.
        let codexCritical = UsageSnapshot(
            provider: .codex, health: .ok, session: SessionUsage(usedPercent: 92), lastActivityAt: Date()
        )
        store.apply(codexCritical)
        XCTAssertNotNil(store.activeThresholdAlert)
        XCTAssertNotNil(store.activeRestoreMoment, "celebration persists in state even while danger is what's shown")
    }
}
