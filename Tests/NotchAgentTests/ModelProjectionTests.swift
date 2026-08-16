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
}
