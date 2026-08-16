import XCTest
@testable import NotchAgent

final class ModelProjectionTests: XCTestCase {
    func testDominantModelIsTheOneWithMostTokens() {
        let tokens: [String: TokenUsage] = [
            "claude-haiku-4-5-20251001": TokenUsage(input: 100, output: 0, cacheWrite: 0, cacheRead: 0),
            "claude-sonnet-5": TokenUsage(input: 10_000, output: 5_000, cacheWrite: 0, cacheRead: 0),
        ]
        XCTAssertEqual(ModelProjection.dominantModel(modelTokens: tokens), "claude-sonnet-5")
    }

    func testDominantModelIsNilWhenNoUsage() {
        XCTAssertNil(ModelProjection.dominantModel(modelTokens: [:]))
    }

    func testAlternatesRatioReflectsRealPricing() {
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0)
        let alternates = ModelProjection.alternates(
            dominantModel: "claude-sonnet-5",
            sessionTokens: usage,
            candidates: ["claude-haiku-4-5-20251001", "claude-sonnet-5", "claude-opus-5", "claude-fable-5"]
        )
        let byShortName = Dictionary(uniqueKeysWithValues: alternates.map { ($0.shortName, $0.priceRatio) })
        // Sonnet itself is excluded — it's the dominant model, already the solid line.
        XCTAssertNil(byShortName["Sonnet"])
        // Sonnet: 3+15=18. Haiku: 1+5=6 -> 6/18. Opus: 5+25=30 -> 30/18. Fable: 10+50=60 -> 60/18.
        XCTAssertEqual(byShortName["Haiku"] ?? -1, 6.0 / 18.0, accuracy: 0.001)
        XCTAssertEqual(byShortName["Opus"] ?? -1, 30.0 / 18.0, accuracy: 0.001)
        XCTAssertEqual(byShortName["Fable"] ?? -1, 60.0 / 18.0, accuracy: 0.001)
    }

    func testAlternatesEmptyWhenDominantModelHasNoKnownPrice() {
        let usage = TokenUsage(input: 100, output: 100, cacheWrite: 0, cacheRead: 0)
        let alternates = ModelProjection.alternates(
            dominantModel: "totally-unknown-model",
            sessionTokens: usage,
            candidates: ["claude-sonnet-5"]
        )
        XCTAssertTrue(alternates.isEmpty)
    }

    func testAlternatesEmptyWhenSessionHasZeroTokens() {
        let alternates = ModelProjection.alternates(
            dominantModel: "claude-sonnet-5",
            sessionTokens: .zero,
            candidates: ["claude-haiku-4-5-20251001", "claude-opus-5"]
        )
        XCTAssertTrue(alternates.isEmpty)
    }

    func testShortNameMapsKnownFamilies() {
        XCTAssertEqual(ModelProjection.shortName(for: "claude-haiku-4-5-20251001"), "Haiku")
        XCTAssertEqual(ModelProjection.shortName(for: "claude-sonnet-5"), "Sonnet")
        XCTAssertEqual(ModelProjection.shortName(for: "claude-opus-5"), "Opus")
        XCTAssertEqual(ModelProjection.shortName(for: "claude-fable-5"), "Fable")
        XCTAssertEqual(ModelProjection.shortName(for: "gpt-5"), "gpt-5", "unknown family falls back to the raw id")
    }

    // MARK: - REGRESSÃO: final whole-branch review findings (2026-08-15)

    /// Finding 1: a real transcript model id (e.g. "claude-opus-4-8") is
    /// often NOT byte-identical to a ClaudeQuotaProbe.modelRotation id (e.g.
    /// "claude-opus-5") even though it's the same tier. Excluding the
    /// dominant model by exact string equality lets that tier appear twice —
    /// once as the dominant line, once as a duplicate dashed alternate.
    func testAlternatesExcludesDominantModelByFamilyNotExactID() {
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0)
        let alternates = ModelProjection.alternates(
            dominantModel: "claude-opus-4-8", // NOT in modelRotation, but same family as claude-opus-5
            sessionTokens: usage,
            candidates: ["claude-haiku-4-5-20251001", "claude-sonnet-5", "claude-opus-5", "claude-fable-5"]
        )
        let shortNames = Set(alternates.map(\.shortName))
        XCTAssertEqual(shortNames, ["Haiku", "Sonnet", "Fable"], "Opus must be excluded by family match, not exact id")
    }

    /// Finding 2/3: Fable 5 is metered on a separate quota pool from the
    /// shared Haiku/Sonnet/Opus pool the chart's % axis represents, so it
    /// must never be returned as dominant — even when it strictly has the
    /// most tokens. The runner-up shared-pool model should win instead.
    func testDominantModelNeverReturnsFableEvenWhenFableHasMostTokens() {
        let tokens: [String: TokenUsage] = [
            "claude-fable-5": TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0),
            "claude-haiku-4-5-20251001": TokenUsage(input: 100, output: 0, cacheWrite: 0, cacheRead: 0),
            "claude-sonnet-5": TokenUsage(input: 10_000, output: 5_000, cacheWrite: 0, cacheRead: 0),
        ]
        XCTAssertEqual(ModelProjection.dominantModel(modelTokens: tokens), "claude-sonnet-5")
    }

    /// Finding 3: a non-Claude model id (e.g. gpt-5, already priced in
    /// PricingTable for unrelated Codex work) must never become dominant on
    /// this Claude-quota % axis, even with strictly the most tokens.
    func testDominantModelNeverReturnsNonClaudeModelEvenWithMostTokens() {
        let tokens: [String: TokenUsage] = [
            "gpt-5": TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0),
            "claude-haiku-4-5-20251001": TokenUsage(input: 100, output: 0, cacheWrite: 0, cacheRead: 0),
            "claude-sonnet-5": TokenUsage(input: 10_000, output: 5_000, cacheWrite: 0, cacheRead: 0),
        ]
        XCTAssertEqual(ModelProjection.dominantModel(modelTokens: tokens), "claude-sonnet-5")
    }

    /// Finding 3: nothing in the shared pool means no dominant model — never
    /// falls back to Fable or a non-Claude id just because they're present.
    func testDominantModelIsNilWhenOnlyFableAndNonClaudeEntriesExist() {
        let tokens: [String: TokenUsage] = [
            "claude-fable-5": TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0),
            "gpt-5": TokenUsage(input: 500, output: 500, cacheWrite: 0, cacheRead: 0),
        ]
        XCTAssertNil(ModelProjection.dominantModel(modelTokens: tokens))
    }
}
