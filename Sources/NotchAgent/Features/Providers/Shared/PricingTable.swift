import Foundation

/// USD per million tokens. Values mirror public pricing pages and are only used
/// for local *estimates* — the UI always labels results as estimated.
public struct ModelPricing: Sendable, Equatable {
    public var inputPerMTok: Double
    public var outputPerMTok: Double
    public var cacheWritePerMTok: Double
    public var cacheReadPerMTok: Double

    public init(input: Double, output: Double, cacheWrite: Double, cacheRead: Double) {
        self.inputPerMTok = input
        self.outputPerMTok = output
        self.cacheWritePerMTok = cacheWrite
        self.cacheReadPerMTok = cacheRead
    }
}

public enum PricingTable {
    /// Longest-prefix match wins, so keep more specific prefixes first.
    static let entries: [(prefix: String, pricing: ModelPricing)] = [
        ("claude-opus-5", ModelPricing(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5)),
        ("claude-fable-5", ModelPricing(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 1.0)),
        ("claude-fable", ModelPricing(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5)),
        ("claude-opus", ModelPricing(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5)),
        ("claude-sonnet", ModelPricing(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3)),
        ("claude-haiku", ModelPricing(input: 1, output: 5, cacheWrite: 1.25, cacheRead: 0.1)),
        ("claude-3-5-haiku", ModelPricing(input: 0.8, output: 4, cacheWrite: 1, cacheRead: 0.08)),
        ("claude-3-opus", ModelPricing(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5)),
        ("claude-3-haiku", ModelPricing(input: 0.25, output: 1.25, cacheWrite: 0.3, cacheRead: 0.03)),
        ("claude", ModelPricing(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3)),
        ("gpt-5", ModelPricing(input: 1.25, output: 10, cacheWrite: 0, cacheRead: 0.125)),
        ("gpt-4", ModelPricing(input: 2.5, output: 10, cacheWrite: 0, cacheRead: 1.25)),
        ("gemini-2.5-pro", ModelPricing(input: 1.25, output: 10, cacheWrite: 0, cacheRead: 0.31)),
        ("gemini-2.5-flash", ModelPricing(input: 0.3, output: 2.5, cacheWrite: 0, cacheRead: 0.075)),
        ("gemini", ModelPricing(input: 1.25, output: 10, cacheWrite: 0, cacheRead: 0.31)),
    ]

    public static func pricing(forModel model: String) -> ModelPricing? {
        entries.first { model.hasPrefix($0.prefix) }?.pricing
    }

    /// `usage.input` must already exclude cached tokens for providers that
    /// report cache reads separately (Claude does; Codex is normalized upstream).
    /// Returns `nil` when `model` isn't in `entries` (new/renamed release, or an
    /// "unknown" alias) — the model's cost is genuinely unknown, never invented
    /// as a verified-looking $0. Callers that need a number for arithmetic must
    /// coalesce explicitly (`?? 0`) so the exclusion stays visible at the call site.
    public static func costUSD(model: String, usage: TokenUsage) -> Double? {
        guard let p = pricing(forModel: model) else { return nil }
        return Double(usage.input) / 1e6 * p.inputPerMTok
            + Double(usage.output) / 1e6 * p.outputPerMTok
            + Double(usage.cacheWrite) / 1e6 * p.cacheWritePerMTok
            + Double(usage.cacheRead) / 1e6 * p.cacheReadPerMTok
    }
}
