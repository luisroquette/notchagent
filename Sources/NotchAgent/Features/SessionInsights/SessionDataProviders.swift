import Foundation
import AgentMeterCore

/// Fonte real do engine: transcripts Claude (~/.claude/projects/**/*.jsonl)
/// e rollouts Codex (~/.codex/sessions). Atribuição de subagente = arquivos
/// "agent-*.jsonl" vs arquivos principais (estrutura real do diretório).
final class ClaudeSessionDataProvider: SessionDataProvider, @unchecked Sendable {
    private let roots: [URL]
    private let lookbackHours: Double
    /// Memo incremental por arquivo. Transcripts vivos só leem os bytes novos;
    /// arquivos truncados/reescritos voltam ao parse completo.
    private let lock = NSLock()
    private var memo: [String: (stamp: FileStamp, offset: UInt64, records: [PayloadBuilder.MessageRecord])] = [:]

    init(roots: [URL] = ClaudeProvider.defaultRoots, lookbackHours: Double = 6) {
        self.roots = roots
        self.lookbackHours = lookbackHours
    }

    private func sessionFiles() -> [URL] {
        let cutoff = Date().addingTimeInterval(-lookbackHours * 3600)
        return roots.flatMap { recentFiles(under: $0, ext: "jsonl", modifiedAfter: cutoff, limit: 500) }
    }

    private func records(for url: URL) -> [PayloadBuilder.MessageRecord] {
        let key = url.path
        guard let stamp = FileStamp(url: url) else { return [] }
        lock.lock()
        defer { lock.unlock() }

        if let cached = memo[key], cached.stamp == stamp { return cached.records }

        do {
            if let cached = memo[key], UInt64(stamp.size) >= cached.offset {
                let chunk = try ClaudeTranscriptParser.parseMessages(at: url, from: cached.offset)
                let records = cached.records + chunk.records
                memo[key] = (stamp, chunk.consumed, records)
                return records
            }
            let parsed = try ClaudeTranscriptParser.parseMessages(at: url)
            memo[key] = (stamp, parsed.consumed, parsed.records)
            return parsed.records
        } catch {
            Log.providers.error("insights: failed to parse \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return memo[key]?.records ?? []
        }
    }

    func messages(provider: ProviderID) async -> [PayloadBuilder.MessageRecord] {
        sessionFiles().flatMap { records(for: $0) }
    }

    func agentSplit(provider: ProviderID) async -> SessionInsightsPayload.AgentSplit? {
        var main = TokenUsage.zero
        var subagent = TokenUsage.zero
        for url in sessionFiles() {
            let isAgentFile = url.lastPathComponent.hasPrefix("agent-")
            for record in records(for: url) {
                if isAgentFile { subagent += record.tokens } else { main += record.tokens }
            }
        }
        guard main.total > 0 || subagent.total > 0 else { return nil }
        return .init(main: main, subagent: subagent)
    }
}

struct CodexSessionDataProvider: SessionDataProvider {
    private let root: URL

    init(root: URL = AppPaths.home.appendingPathComponent(".codex/sessions")) {
        self.root = root
    }

    /// Registro do rollout mais novo (nome "rollout-<stamp>" = ordem
    /// cronológica). Totais do rollout são cumulativos — um registro por
    /// rollout, timestamp = início do rollout (mesma semântica de janela
    /// usada pelo CodexProvider).
    static func record(for url: URL) throws -> PayloadBuilder.MessageRecord? {
        guard let info = try CodexRolloutParser.latestTokenInfo(at: url) else { return nil }
        return PayloadBuilder.MessageRecord(
            timestamp: CodexProvider.rolloutStart(from: url) ?? info.timestamp ?? .distantPast,
            requestId: url.lastPathComponent,
            model: info.model,
            tokens: info.totals,
            toolNames: []
        )
    }

    func messages(provider: ProviderID) async -> [PayloadBuilder.MessageRecord] {
        let cutoff = Date().addingTimeInterval(-6 * 3600)
        let files = recentFiles(under: root, ext: "jsonl", modifiedAfter: cutoff, limit: 100)
        guard let newest = files.max(by: { $0.lastPathComponent < $1.lastPathComponent }) else { return [] }
        do {
            if let record = try Self.record(for: newest) { return [record] }
        } catch {
            Log.providers.error("insights: failed to parse \(newest.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return []
    }

    func agentSplit(provider: ProviderID) async -> SessionInsightsPayload.AgentSplit? { nil }
}

/// Roteador usado pelo RefreshScheduler — uma implementação de
/// SessionDataProvider para os providers com fonte de sessão.
struct LiveSessionDataProvider: SessionDataProvider {
    private let claude = ClaudeSessionDataProvider()
    private let codex = CodexSessionDataProvider()

    func messages(provider: ProviderID) async -> [PayloadBuilder.MessageRecord] {
        switch provider {
        case .claudeCode: await claude.messages(provider: provider)
        case .codex: await codex.messages(provider: provider)
        default: []
        }
    }

    func agentSplit(provider: ProviderID) async -> SessionInsightsPayload.AgentSplit? {
        switch provider {
        case .claudeCode: await claude.agentSplit(provider: provider)
        default: nil
        }
    }
}
