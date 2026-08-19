import XCTest
@testable import NotchAgent

final class MascotMindCoreTests: XCTestCase {
    private var rng = SplitMix64(seed: 42)
    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    func testRecomputeMoodStates() {
        XCTAssertEqual(MascotMindCore.recomputeMood(energy: 0.9, affection: 0.9, burnHigh: true), .alert)
        XCTAssertEqual(MascotMindCore.recomputeMood(energy: 0.1, affection: 0.5, burnHigh: false), .sleepy)
        XCTAssertEqual(MascotMindCore.recomputeMood(energy: 0.9, affection: 0.9, burnHigh: false), .curious)
        XCTAssertEqual(MascotMindCore.recomputeMood(energy: 0.5, affection: 0.2, burnHigh: false), .calm)
    }

    func testEvolveTickDecaysEnergyAndClamps() {
        var state = MascotMindState(energy: 1)
        MascotMindCore.evolveTick(state: &state, now: now, idleSeconds: 0, burnHigh: false)
        XCTAssertEqual(state.energy, 1, accuracy: 0.0001, "zero idle time must not decay energy")

        MascotMindCore.evolveTick(state: &state, now: now.addingTimeInterval(60), idleSeconds: 60, burnHigh: false)
        XCTAssertEqual(state.energy, 1 - 60 * 0.00005, accuracy: 0.0001)
        XCTAssertEqual(state.lastSeen, now.addingTimeInterval(60))
    }

    func testNudgeRespectsCooldown() {
        var state = MascotMindState()
        state.gestureCooldownUntil = now.addingTimeInterval(30)
        let gesture = MascotMindCore.nudge(state: &state, moment: .quotaReset, now: now, rng: &rng)
        XCTAssertEqual(gesture, .none, "within cooldown, no reaction may fire")
        XCTAssertNil(state.lastGesture)
    }

    func testNudgeCanBeIgnoredButSometimesReacts() {
        var state = MascotMindState(affection: 0)  // ignoreChance máximo: 0.35
        var reacts = 0
        var ignores = 0
        for _ in 0..<200 {
            var s = MascotMindState(affection: 0)
            let g = MascotMindCore.nudge(state: &s, moment: .quotaReset, now: now, rng: &rng)
            if g == .ignored { ignores += 1 } else if g != .none { reacts += 1 }
        }
        XCTAssertGreaterThan(ignores, 0, "with affection 0 the mascot must sometimes ignore")
        XCTAssertGreaterThan(reacts, 0, "and sometimes react")
    }

    func testTeimosiaForcesReactionAfterTwoIgnores() {
        var state = MascotMindState(affection: 0, ignoresInARow: 2)
        let gesture = MascotMindCore.nudge(state: &state, moment: .quotaReset, now: now, rng: &rng)
        XCTAssertNotEqual(gesture, .ignored, "two consecutive ignores force the third reaction")
        XCTAssertEqual(state.ignoresInARow, 0)
        XCTAssertNotNil(state.gestureCooldownUntil)
    }

    func testReactionSetsCooldownOf90Seconds() {
        // Teimosia garante a reação — o teste não pode depender de sorte.
        var state = MascotMindState(affection: 1, ignoresInARow: 2)
        let gesture = MascotMindCore.nudge(state: &state, moment: .quotaReset, now: now, rng: &rng)
        XCTAssertNotEqual(gesture, .ignored)
        XCTAssertEqual(state.gestureCooldownUntil, now.addingTimeInterval(DelightCatalog.reactionCooldown))
    }

    func testChooseGestureNeverPicksLastGesture() {
        let state = MascotMindState(mood: .curious, lastGesture: .blink)
        for _ in 0..<50 {
            let g = MascotMindCore.chooseGesture(state: state, moment: .randomExpand, rng: &rng)
            XCTAssertNotEqual(g, .blink, "the same gesture never repeats consecutively")
        }
    }

    func testChooseGestureOnlyPicksCatalogGestures() {
        let state = MascotMindState(mood: .calm)
        for _ in 0..<50 {
            let g = MascotMindCore.chooseGesture(state: state, moment: .quotaReset, rng: &rng)
            XCTAssertTrue(DelightCatalog.gestures(for: .quotaReset).contains(g))
        }
    }

    func testSelfInitiatedGestureRespectsCooldownAndSetsIt() {
        var state = MascotMindState(energy: 1)
        for _ in 0..<50 {
            let g = MascotMindCore.selfInitiatedGesture(state: &state, now: now, rng: &rng)
            if g != .none {
                XCTAssertNotNil(state.gestureCooldownUntil)
                return
            }
        }
        XCTFail("with full energy, 50 attempts must self-initiate at least once")
    }

    func testFirstExpandOfDay() {
        let state = MascotMindState(lastExpandedDay: "2026-08-18")
        XCTAssertTrue(MascotMindCore.firstExpandOfDay(state: state, dayKey: "2026-08-19"))
        XCTAssertFalse(MascotMindCore.firstExpandOfDay(state: state, dayKey: "2026-08-18"))
        XCTAssertTrue(MascotMindCore.firstExpandOfDay(state: MascotMindState(), dayKey: "2026-08-19"))
    }
}
