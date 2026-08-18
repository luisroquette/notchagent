import Foundation
import AgentMeterCore

/// Regras de sugestão sobre o SessionInsightsPayload — a camada "por onde o
/// usuário está gastando" que os dados de snapshot não respondem. Funções
/// puras: payload entra, conselhos saem (padrão isFableModel).
enum PayloadAdvisor {
    static let agentDominanceShare = 0.50
    static let messageDominanceShare = 0.30

    static func advise(_ payload: SessionInsightsPayload) -> [DecisionAdvice] {
        var advice: [DecisionAdvice] = []
        let total = max(payload.aggregate.total, 1)

        if let dominant = payload.tokensByTool.max(by: { $0.value.total < $1.value.total }),
           Double(dominant.value.total) / Double(total) >= PayloadBuilder.toolDominanceShare {
            let pct = Int((Double(dominant.value.total) / Double(total) * 100).rounded())
            advice.append(DecisionAdvice(
                title: "Ferramenta dominante: \(dominant.key)",
                detail: "\(dominant.key) consome \(pct)% dos tokens desta sessão; retornos grandes podem ser recortados.",
                severity: .normal
            ))
        }

        if let split = payload.agentSplit {
            let subTotal = split.main.total + split.subagent.total
            if subTotal > 0, Double(split.subagent.total) / Double(subTotal) >= agentDominanceShare {
                let pct = Int((Double(split.subagent.total) / Double(subTotal) * 100).rounded())
                advice.append(DecisionAdvice(
                    title: "Subagentes dominando",
                    detail: "Subagentes consomem \(pct)% da sessão; cada um relê o contexto inteiro.",
                    severity: .warning
                ))
            }
        }

        if let heaviest = payload.topMessages.first,
           Double(heaviest.tokens.total) / Double(total) >= messageDominanceShare {
            let pct = Int((Double(heaviest.tokens.total) / Double(total) * 100).rounded())
            advice.append(DecisionAdvice(
                title: "Operação única pesada",
                detail: "Uma única operação (\(pct)% da sessão) consumiu \(Format.tokens(heaviest.tokens.total)).",
                severity: .normal
            ))
        }

        return advice
    }
}
