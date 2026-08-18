import XCTest
@testable import NotchAgent

final class WeatherModelTests: XCTestCase {
    // MARK: WMO mapping

    func testWMOMappingClear() {
        XCTAssertEqual(WeatherCondition.from(wmoCode: 0), .clear)
    }

    func testWMOMappingPartlyCloudy() {
        XCTAssertEqual(WeatherCondition.from(wmoCode: 1), .partlyCloudy)
        XCTAssertEqual(WeatherCondition.from(wmoCode: 2), .partlyCloudy)
    }

    func testWMOMappingCloudyAndFog() {
        XCTAssertEqual(WeatherCondition.from(wmoCode: 3), .cloudy)
        // Fog/rimé reads as cloudy — no dedicated fog effect.
        XCTAssertEqual(WeatherCondition.from(wmoCode: 45), .cloudy)
        XCTAssertEqual(WeatherCondition.from(wmoCode: 48), .cloudy)
    }

    func testWMOMappingRain() {
        for code in [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82] {
            XCTAssertEqual(WeatherCondition.from(wmoCode: code), .rain, "code \(code)")
        }
    }

    func testWMOMappingSnow() {
        for code in [71, 73, 75, 77, 85, 86] {
            XCTAssertEqual(WeatherCondition.from(wmoCode: code), .snow, "code \(code)")
        }
    }

    func testWMOMappingStorm() {
        for code in [95, 96, 99] {
            XCTAssertEqual(WeatherCondition.from(wmoCode: code), .storm, "code \(code)")
        }
    }

    func testWMOUnknownCodeIsNil() {
        XCTAssertNil(WeatherCondition.from(wmoCode: 999))
        XCTAssertNil(WeatherCondition.from(wmoCode: -1))
    }

    // MARK: Snapshot round-trip

    func testSnapshotRoundTripsThroughJSON() throws {
        let snap = WeatherSnapshot(
            condition: .rain,
            temperatureC: 24.3,
            isDay: true,
            city: "São Paulo, BR",
            capturedAt: Date(timeIntervalSince1970: 1_756_000_000)
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: data)
        XCTAssertEqual(decoded, snap)
    }
}
