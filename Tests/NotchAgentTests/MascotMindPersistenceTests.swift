import XCTest
import Foundation
@testable import NotchAgent

final class MascotMindPersistenceTests: XCTestCase {
    private var tempDir: URL!
    private var persistence: MascotMindPersistence!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mascot-mind-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        persistence = MascotMindPersistence(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testRoundTrip() {
        var state = MascotMindState()
        state.mood = .sleepy
        state.energy = 0.42
        state.affection = 0.77
        state.lastExpandedDay = "2026-08-19"
        state.lastGesture = .yawn
        state.ignoresInARow = 1
        state.gestureCooldownUntil = Date(timeIntervalSince1970: 1_756_100_000)

        persistence.save(state)
        let loaded = persistence.load()

        XCTAssertEqual(loaded, state)
    }

    func testMissingFileLoadsFreshState() {
        let loaded = persistence.load()
        XCTAssertEqual(loaded, MascotMindState())
    }

    func testCorruptFileLoadsFreshState() {
        try? "not json at all".write(to: tempDir.appendingPathComponent("mascot-mind.json"), atomically: true, encoding: .utf8)
        let loaded = persistence.load()
        XCTAssertEqual(loaded, MascotMindState())
    }

    func testLegacyPayloadWithoutNewFieldsLoadsWithDefaults() {
        let legacy = """
        {"mood":"curious","energy":0.9}
        """
        try? legacy.write(to: tempDir.appendingPathComponent("mascot-mind.json"), atomically: true, encoding: .utf8)
        let loaded = persistence.load()
        XCTAssertEqual(loaded.mood, .curious)
        XCTAssertEqual(loaded.energy, 0.9)
        XCTAssertEqual(loaded.affection, 0.5, "missing fields must fall back to defaults")
        XCTAssertNil(loaded.lastGesture)
    }
}
