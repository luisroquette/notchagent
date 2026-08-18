import Foundation
import AgentMeterCore

/// Ponte render-only entre o payload e as views. Cada helper retorna um campo
/// VERBATIM do payload — nenhuma view calcula nada (paridade por construção).
/// Testado bit-for-bit em SessionInsightsParityTests.
enum ViewBindings {
    /// Linha da barrinha: exatamente payload.preview.line.
    static func notchPreviewLine(_ payload: SessionInsightsPayload?) -> String? {
        payload?.preview.line
    }

    /// Modelo dominante do painel: máx de tokensByModel.
    static func panelDominantModel(_ payload: SessionInsightsPayload?) -> String? {
        payload?.tokensByModel.max(by: { $0.value.total < $1.value.total })?.key
    }

    /// Corpo da notificação: exatamente payload.burnout.detail.
    static func burnoutBody(_ payload: SessionInsightsPayload?) -> String? {
        payload?.burnout?.detail
    }
}
