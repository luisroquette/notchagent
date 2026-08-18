import XCTest
@testable import NotchAgent

/// Paridade por construção: as 3 superfícies (notch, painel, notificação)
/// leem o MESMO payload — os helpers são a única ponte e não recalculam nada.
final class SessionInsightsParityTests: XCTestCase {
    func testAllThreeSurfacesReadTheSamePayloadBitForBit() {
        let payload = SamplePayloads.makeFullPayload()

        // Barrinha: renderiza payload.preview.line VERBATIM (nunca recalcula)
        XCTAssertEqual(ViewBindings.notchPreviewLine(payload), payload.preview.line)

        // Painel: modelo dominante = máx de payload.tokensByModel (mesmo objeto)
        XCTAssertEqual(ViewBindings.panelDominantModel(payload),
                       payload.tokensByModel.max(by: { $0.value.total < $1.value.total })?.key)

        // Notificação: corpo = payload.burnout.detail VERBATIM
        XCTAssertEqual(ViewBindings.burnoutBody(payload), payload.burnout?.detail)
    }

    func testPreviewLineSurvivesPayloadMutationWithoutRecalculation() {
        // Se o campo preview for alterado no payload, a view mostra o ALTERADO —
        // prova de que a view não recalcula nada em lugar nenhum.
        var payload = SamplePayloads.makeFullPayload()
        payload.preview = .init(line: "FORÇADO", tier: .alert)
        XCTAssertEqual(ViewBindings.notchPreviewLine(payload), "FORÇADO")
    }
}

private enum SamplePayloads {
    static func makeFullPayload() -> SessionInsightsPayload {
        var payload = PayloadBuilder.build(
            provider: .claudeCode,
            window: DateInterval(start: .distantPast, end: .distantFuture),
            records: [
                .init(timestamp: .now, requestId: "r1", model: "claude-sonnet-5",
                      tokens: TokenUsage(input: 60_000, output: 10_000, cacheWrite: 0, cacheRead: 30_000),
                      toolNames: ["Read"]),
            ])
        payload.burnout = .init(title: "CALMA AÍ", detail: "Nesse ritmo você ficará sem token às 15:00.", exhaustsAt: nil)
        return payload
    }
}
