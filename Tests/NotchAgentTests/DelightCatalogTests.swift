import XCTest
@testable import NotchAgent

final class DelightCatalogTests: XCTestCase {
    func testEveryContextHasABobExceptPoke() {
        for context in MascotContext.allCases {
            let options = DelightCatalog.bobVariants(for: context)
            if context == .poke {
                XCTAssertTrue(options.isEmpty, "poke uses poke variants, not bobs")
            } else {
                XCTAssertFalse(options.isEmpty, "\(context.rawValue) has no bob vocabulary")
            }
        }
    }

    func testExpandContextMapping() {
        XCTAssertEqual(DelightCatalog.expandContext(mood: .curious, firstExpandOfDay: true), .greeting)
        XCTAssertEqual(DelightCatalog.expandContext(mood: .curious, firstExpandOfDay: false), .playful)
        XCTAssertEqual(DelightCatalog.expandContext(mood: .alert, firstExpandOfDay: false), .tense)
        XCTAssertEqual(DelightCatalog.expandContext(mood: .sleepy, firstExpandOfDay: false), .drowsy)
        XCTAssertEqual(DelightCatalog.expandContext(mood: .calm, firstExpandOfDay: false), .calm)
    }

    func testSelectBobRoundRobinNeverRepeatsConsecutively() {
        for context in MascotContext.allCases
        where DelightCatalog.bobVariants(for: context).count >= 2 {
            var cursor = 0
            var previous: BobVariant?
            for _ in 0..<4 {
                let selected = DelightCatalog.selectBob(context: context, cursor: &cursor)
                XCTAssertNotEqual(selected, previous, "\(context.rawValue) repeated \(selected.rawValue) consecutively")
                previous = selected
            }
            XCTAssertEqual(cursor, 4, "each selection advances the cursor")
        }
    }

    func testSelectBobCyclesThroughTheWholeSet() {
        var cursor = 0
        let options = DelightCatalog.bobVariants(for: .playful)
        var seen: Set<BobVariant> = []
        for _ in 0..<options.count {
            seen.insert(DelightCatalog.selectBob(context: .playful, cursor: &cursor))
        }
        XCTAssertEqual(seen, Set(options), "round-robin must visit every variant before repeating")
    }

    func testSelectPokeCyclesThroughAllThree() {
        var cursor = 0
        var seen: Set<PokeVariant> = []
        for _ in 0..<PokeVariant.allCases.count {
            seen.insert(DelightCatalog.selectPoke(cursor: &cursor))
        }
        XCTAssertEqual(seen, Set(PokeVariant.allCases))
        let fourth = DelightCatalog.selectPoke(cursor: &cursor)
        XCTAssertEqual(fourth, PokeVariant.allCases[0], "after a full cycle the sequence restarts")
    }

    func testVocabularyAssignments() {
        // Round 3: cada gesto novo pertence ao contexto certo.
        XCTAssertTrue(DelightCatalog.bobVariants(for: .greeting).contains(.bow), "greeting bows")
        XCTAssertTrue(DelightCatalog.bobVariants(for: .relief).contains(.bow), "relief bows too")
        XCTAssertTrue(DelightCatalog.bobVariants(for: .tense).contains(.shiver), "tense shivers")
        XCTAssertTrue(DelightCatalog.bobVariants(for: .playful).contains(.doubleTake), "playful double-takes")
        XCTAssertTrue(DelightCatalog.bobVariants(for: .calm).contains(.doubleTake), "calm double-takes too")
        XCTAssertFalse(DelightCatalog.bobVariants(for: .drowsy).contains(.shiver), "a drowsy mascot has no energy to shiver")
    }

    func testVariantCursorPersistsInState() throws {
        var state = MascotMindState(variantCursor: 7)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(MascotMindState.self, from: data)
        XCTAssertEqual(decoded.variantCursor, 7)
    }

    func testLegacyStateWithoutCursorDefaultsToZero() throws {
        let legacy = """
        {"mood":"curious","energy":0.9}
        """
        let decoded = try JSONDecoder().decode(MascotMindState.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.variantCursor, 0, "legacy saves must round-robin from the start")
    }
}
