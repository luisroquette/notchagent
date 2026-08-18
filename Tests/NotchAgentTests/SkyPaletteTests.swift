import XCTest
@testable import NotchAgent

final class SkyPaletteTests: XCTestCase {
    func testMiddayIsVividBlue() {
        let p = SkyPalette.make(phase: .day, transition: 0, condition: .clear)
        XCTAssertEqual(p.top, SkyPalette.dayTop)
        XCTAssertEqual(p.bottom, SkyPalette.dayBottom)
        // Blue dominates the top.
        XCTAssertGreaterThan(p.top.b, p.top.r)
    }

    func testNightIsDeepDarkBlue() {
        let p = SkyPalette.make(phase: .night, transition: 0, condition: .clear)
        XCTAssertEqual(p.top, SkyPalette.nightTop)
        XCTAssertLessThan(p.top.r, 0.1)
    }

    func testDuskMidpointHasSunsetFire() {
        // The exact sunset moment: horizon burns orange/pink.
        let p = SkyPalette.make(phase: .dusk, transition: 0.5, condition: .clear)
        XCTAssertGreaterThan(p.bottom.r, 0.75, "horizon must ignite")
        XCTAssertGreaterThan(p.bottom.r, p.bottom.b, "fire is warm, not blue")
    }

    func testDuskLateTurnsBlueHour() {
        let p = SkyPalette.make(phase: .dusk, transition: 0.85, condition: .clear)
        // Blue hour: violet-ish bottom, no more fire.
        XCTAssertLessThan(p.bottom.r, 0.45)
        XCTAssertGreaterThan(p.bottom.b, p.bottom.r)
    }

    func testDawnMidpointHasGoldenFire() {
        let p = SkyPalette.make(phase: .dawn, transition: 0.5, condition: .clear)
        XCTAssertGreaterThan(p.bottom.r, 0.5)
        XCTAssertGreaterThan(p.bottom.g, 0.3)
    }

    func testFogDesaturatesAlmostEverything() {
        let clear = SkyPalette.make(phase: .day, transition: 0, condition: .clear)
        let fog = SkyPalette.make(phase: .day, transition: 0, condition: .fog)
        // Channels collapse toward each other (grey).
        let clearSpread = clear.top.b - clear.top.r
        let fogSpread = fog.top.b - fog.top.r
        XCTAssertLessThan(fogSpread, clearSpread * 0.4)
    }

    func testCloudyDullsButKeepsHue() {
        let p = SkyPalette.make(phase: .dusk, transition: 0.5, condition: .cloudy)
        // Still warm at the horizon, but far duller than clear.
        XCTAssertGreaterThan(p.bottom.r, p.bottom.b)
        let clear = SkyPalette.make(phase: .dusk, transition: 0.5, condition: .clear)
        XCTAssertLessThan(p.bottom.r, clear.bottom.r)
    }

    func testSaturationTable() {
        XCTAssertEqual(SkyPalette.saturation(for: .clear), 1.0)
        XCTAssertEqual(SkyPalette.saturation(for: .fog), 0.15)
        XCTAssertEqual(SkyPalette.saturation(for: .thunderstorm), 0.3)
    }
}
