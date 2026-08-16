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

    /// The model with the most tokens spent in the current window — the
    /// model the chart's existing solid/dashed history line represents.
    public static func dominantModel(modelTokens: [String: TokenUsage]) -> String? {
        modelTokens.max { $0.value.total < $1.value.total }?.key
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
            .filter { $0 != dominantModel }
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
}
