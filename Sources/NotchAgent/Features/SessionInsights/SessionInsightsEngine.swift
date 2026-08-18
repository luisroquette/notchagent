import Foundation
import AgentMeterCore

/// Fonte de dados do engine. Nesta etapa, a implementação vazia retorna []
/// SEMPRE — a etapa 3 implementa as versões reais (Claude/Codex). O engine
/// não conhece parsers.
protocol SessionDataProvider: Sendable {
    func messages(provider: ProviderID) async -> [PayloadBuilder.MessageRecord]
    func agentSplit(provider: ProviderID) async -> SessionInsightsPayload.AgentSplit?
}

struct EmptySessionDataProvider: SessionDataProvider {
    func messages(provider: ProviderID) async -> [PayloadBuilder.MessageRecord] { [] }
    func agentSplit(provider: ProviderID) async -> SessionInsightsPayload.AgentSplit? { nil }
}

enum SessionInsightsEngine {
    /// Janela da sessão a partir do snapshot (session.startedAt...resetsAt;
    /// fallback: lastActivityAt ± 2,5h). Retorna nil quando não há janela.
    static func window(from snapshot: UsageSnapshot?, now: Date = Date()) -> DateInterval? {
        guard let snapshot else { return nil }
        if let session = snapshot.session, let startedAt = session.startedAt {
            return DateInterval(start: startedAt, end: session.resetsAt ?? now)
        }
        if let lastActivityAt = snapshot.lastActivityAt {
            return DateInterval(start: lastActivityAt.addingTimeInterval(-2.5 * 3600),
                                end: lastActivityAt.addingTimeInterval(2.5 * 3600))
        }
        return nil
    }

    /// Constrói payloads para os providers com snapshot, janela e mensagens;
    /// com fonte vazia, retorna [:] (produção inalterada).
    static func refresh(
        snapshots: [ProviderID: UsageSnapshot],
        dataProvider: any SessionDataProvider = EmptySessionDataProvider(),
        burnout: [ProviderID: SessionInsightsPayload.BurnoutSignal] = [:],
        now: Date = Date()
    ) async -> [ProviderID: SessionInsightsPayload] {
        var payloads: [ProviderID: SessionInsightsPayload] = [:]
        for (provider, snapshot) in snapshots {
            guard let window = window(from: snapshot, now: now) else { continue }
            let records = await dataProvider.messages(provider: provider)
            guard !records.isEmpty else { continue }
            let agentSplit = await dataProvider.agentSplit(provider: provider)
            payloads[provider] = PayloadBuilder.build(
                provider: provider, window: window, records: records,
                agentSplit: agentSplit, burnout: burnout[provider], generatedAt: now)
        }
        return payloads
    }
}
