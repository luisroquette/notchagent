import Foundation
import AgentMeterCore

/// Envelope único entre o motor de insights e as 3 views (notch, painel,
/// notificação). As views são render-only: leem campos, nunca recalculam —
/// paridade por construção (lição do menubar-json do CodeBurn).
public struct SessionInsightsPayload: Codable, Equatable, Sendable {
    /// Severidade visual do preview (define a cor/tom nas 3 views).
    public enum Tier: String, Codable, Sendable { case ok, watch, alert }

    /// O que a barrinha mostra. Derivado EXCLUSIVAMENTE pelo PayloadBuilder —
    /// nenhuma view recalcula esta linha (paridade por construção).
    public struct Preview: Codable, Equatable, Sendable {
        public var line: String
        public var tier: Tier
    }

    /// Sinal de esgotamento projetado (CALMA AÍ). Reservado: nasce nil;
    /// a sessão do alerta passa a preenchê-lo. Codable desde já para o
    /// contrato não apodrecer.
    public struct BurnoutSignal: Codable, Equatable, Sendable {
        public var title: String
        public var detail: String
        public var exhaustsAt: Date?
    }

    /// Versão do envelope. Incrementar apenas com mudança de forma;
    /// campos novos entram como opcionais (decode de payloads antigos continua).
    public var schemaVersion: Int
    public var generatedAt: Date
    public var provider: ProviderID
    public var window: DateInterval
    /// Soma dos 4 componentes na janela. Componente zero significa zero REAL
    /// naquela fonte, nunca "desconhecido" (ausência é nil).
    public var aggregate: TokenUsage
    /// cacheRead / aggregate.total, 0...1.
    public var cacheShare: Double
    /// Top 3 ferramentas por tokens (painel).
    public var tokensByTool: [String: TokenUsage]
    /// Top 3 modelos por tokens (painel).
    public var tokensByModel: [String: TokenUsage]
    /// nil quando a fonte não distingue agentes (Codex).
    public var agentSplit: AgentSplit?
    /// Top 3 mensagens (painel).
    public var topMessages: [TopMessage]
    /// Linha pronta para a barrinha.
    public var preview: Preview
    /// Reservado (sessão CALMA AÍ).
    public var burnout: BurnoutSignal?

    public struct AgentSplit: Codable, Equatable, Sendable {
        public var main: TokenUsage
        public var subagent: TokenUsage
    }

    public struct TopMessage: Codable, Equatable, Sendable, Identifiable {
        public var id: String { requestId }
        public var requestId: String
        public var timestamp: Date
        public var model: String?
        public var tokens: TokenUsage
        public var toolNames: [String]
    }

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date,
        provider: ProviderID,
        window: DateInterval,
        aggregate: TokenUsage,
        cacheShare: Double,
        tokensByTool: [String: TokenUsage],
        tokensByModel: [String: TokenUsage],
        agentSplit: AgentSplit?,
        topMessages: [TopMessage],
        preview: Preview,
        burnout: BurnoutSignal? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.provider = provider
        self.window = window
        self.aggregate = aggregate
        self.cacheShare = cacheShare
        self.tokensByTool = tokensByTool
        self.tokensByModel = tokensByModel
        self.agentSplit = agentSplit
        self.topMessages = topMessages
        self.preview = preview
        self.burnout = burnout
    }
}
