import Foundation
import AgentMeterCore

/// Única função que deriva um payload. O preview é derivado AQUI e em nenhum
/// outro lugar — as views renderizam, nunca calculam (paridade por construção).
enum PayloadBuilder {
    static let cacheShareMin = 0.25
    static let toolDominanceShare = 0.40
    static let minTokensForPreview = 50_000

    /// Registro neutro de mensagem — o formato que TODA fonte de dados
    /// (parsers Claude/Codex da etapa 3) deve produzir.
    struct MessageRecord: Equatable, Sendable {
        var timestamp: Date
        var requestId: String
        var model: String?
        var tokens: TokenUsage
        var toolNames: [String]
    }

    static func build(
        provider: ProviderID,
        window: DateInterval,
        records: [MessageRecord],
        agentSplit: SessionInsightsPayload.AgentSplit? = nil,
        burnout: SessionInsightsPayload.BurnoutSignal? = nil,
        generatedAt: Date = Date(),
        topN: Int = 3
    ) -> SessionInsightsPayload {
        let inWindow = records.filter { window.contains($0.timestamp) }
        var aggregate = TokenUsage()
        var tokensByTool: [String: TokenUsage] = [:]
        var tokensByModel: [String: TokenUsage] = [:]
        for record in inWindow {
            aggregate += record.tokens
            for tool in record.toolNames {
                tokensByTool[tool, default: .zero] += record.tokens
            }
            let model = record.model ?? "unknown"
            tokensByModel[model, default: .zero] += record.tokens
        }
        let total = max(aggregate.total, 1)
        let cacheShare = Double(aggregate.cacheRead) / Double(total)
        let topMessages = inWindow
            .sorted { $0.tokens.total > $1.tokens.total }
            .prefix(topN)
            .map {
                SessionInsightsPayload.TopMessage(
                    requestId: $0.requestId, timestamp: $0.timestamp, model: $0.model,
                    tokens: $0.tokens, toolNames: $0.toolNames)
            }
        let preview = previewLine(aggregate: aggregate, cacheShare: cacheShare, tools: tokensByTool)
        return SessionInsightsPayload(
            generatedAt: generatedAt,
            provider: provider,
            window: window,
            aggregate: aggregate,
            cacheShare: cacheShare,
            tokensByTool: tokensByTool,
            tokensByModel: tokensByModel,
            agentSplit: agentSplit,
            topMessages: topMessages,
            preview: preview,
            burnout: burnout
        )
    }

    /// Regra pura do preview: cache frio → .watch; ferramenta dominante →
    /// nome dela; senão "Sessão equilibrada".
    static func previewLine(
        aggregate: TokenUsage,
        cacheShare: Double,
        tools: [String: TokenUsage]
    ) -> SessionInsightsPayload.Preview {
        let total = max(aggregate.total, 1)
        if cacheShare < cacheShareMin && aggregate.total >= minTokensForPreview {
            return .init(line: "Cache \(Int((cacheShare * 100).rounded()))%", tier: .watch)
        }
        if let dominant = tools.max(by: { $0.value.total < $1.value.total }),
           Double(dominant.value.total) / Double(total) >= toolDominanceShare {
            let pct = Int((Double(dominant.value.total) / Double(total) * 100).rounded())
            return .init(line: "Topo: \(dominant.key) \(pct)%", tier: .watch)
        }
        return .init(line: "Sessão equilibrada", tier: .ok)
    }
}
