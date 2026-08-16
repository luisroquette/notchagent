import Foundation

/// Projects "what if I'd used a different model" for the burn chart — pure
/// functions, fully unit-tested, mirroring BurnRate's shape (no I/O, no
/// state). See docs/superpowers/specs/2026-08-15-burn-chart-multi-model-projection-design.md.
public enum ModelProjection {
    /// One of the 4 Claude tiers, scaled relative to the dominant model.
    public struct Alternate: Sendable, Equatable, Identifiable {
        public var model: String
        public var shortName: String
        /// costUSD(model, sessionTokens) / costUSD(dominantModel, sessionTokens).
        /// >1 means this model would burn quota faster than what's shown;
        /// <1 means slower.
        public var priceRatio: Double

        public var id: String { model }

        public init(model: String, shortName: String, priceRatio: Double) {
            self.model = model
            self.shortName = shortName
            self.priceRatio = priceRatio
        }
    }

    /// The model with the most tokens spent in the current window, restricted to
    /// the shared Haiku/Sonnet/Opus pool this chart's % axis actually represents.
    /// Fable 5 is excluded even though its own tokens are real — it's metered on
    /// its own separate quota (see the Fable comment in ClaudeProvider.swift), so
    /// it has no % on this axis to be "dominant" of. It still appears as one of
    /// the alternate lines, just never as the highlighted one. Any non-Claude
    /// model id (e.g. a GPT or Gemini entry that happens to appear in the same
    /// transcript) is excluded for the same reason — there's no shared axis to
    /// project it onto either.
    public static func dominantModel(modelTokens: [String: TokenUsage]) -> String? {
        modelTokens
            .filter { isSharedPoolModel($0.key) }
            .max { $0.value.total < $1.value.total }?.key
    }

    /// One alternate per candidate other than `dominantModel`. Silently
    /// skips a candidate PricingTable has no price for (never a
    /// fabricated $0 — see PricingTable.costUSD's contract) and returns
    /// nothing at all when the dominant model itself has no known price,
    /// or when there's nothing to scale (zero tokens this session).
    static func alternates(
        dominantModel: String,
        sessionTokens: TokenUsage,
        candidates: [String] = ClaudeQuotaProbe.modelRotation
    ) -> [Alternate] {
        guard let dominantCost = PricingTable.costUSD(model: dominantModel, usage: sessionTokens),
              dominantCost > 0
        else { return [] }

        return candidates
            .filter { shortName(for: $0) != shortName(for: dominantModel) }
            .compactMap { candidate in
                guard let cost = PricingTable.costUSD(model: candidate, usage: sessionTokens) else { return nil }
                return Alternate(model: candidate, shortName: shortName(for: candidate), priceRatio: cost / dominantCost)
            }
    }

    private static let families: [(key: String, name: String)] = [
        ("haiku", "Haiku"), ("sonnet", "Sonnet"), ("opus", "Opus"), ("fable", "Fable"),
    ]

    /// Short display name for a model id. Falls back to the raw id when
    /// it doesn't match one of the 4 known Claude families (e.g. a Codex
    /// model — out of scope for this feature, see the design spec).
    public static func shortName(for model: String) -> String {
        families.first { model.contains($0.key) }?.name ?? model
    }

    /// True for a model id in the shared Haiku/Sonnet/Opus quota pool this
    /// chart's % axis represents. False for Fable (separately metered) and
    /// for any non-Claude id.
    private static func isSharedPoolModel(_ model: String) -> Bool {
        model.contains("haiku") || model.contains("sonnet") || model.contains("opus")
    }
}
