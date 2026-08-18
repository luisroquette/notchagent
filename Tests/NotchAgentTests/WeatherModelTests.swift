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

    func testWMOMappingCloudy() {
        XCTAssertEqual(WeatherCondition.from(wmoCode: 3), .cloudy)
    }

    func testWMOMappingFog() {
        XCTAssertEqual(WeatherCondition.from(wmoCode: 45), .fog)
        XCTAssertEqual(WeatherCondition.from(wmoCode: 48), .fog)
    }

    func testWMOMappingDrizzle() {
        for code in [51, 53, 55] {
            XCTAssertEqual(WeatherCondition.from(wmoCode: code), .drizzle, "code \(code)")
        }
    }

    func testWMOMappingRain() {
        for code in [61, 63, 80] {
            XCTAssertEqual(WeatherCondition.from(wmoCode: code), .rain, "code \(code)")
        }
    }

    func testWMOMappingHeavyRain() {
        for code in [65, 81, 82] {
            XCTAssertEqual(WeatherCondition.from(wmoCode: code), .heavyRain, "code \(code)")
        }
    }

    func testWMOMappingFreezingRain() {
        for code in [56, 57, 66, 67] {
            XCTAssertEqual(WeatherCondition.from(wmoCode: code), .freezingRain, "code \(code)")
        }
    }

    func testWMOMappingSnow() {
        for code in [71, 73, 77, 85] {
            XCTAssertEqual(WeatherCondition.from(wmoCode: code), .snow, "code \(code)")
        }
    }

    func testWMOMappingHeavySnow() {
        for code in [75, 86] {
            XCTAssertEqual(WeatherCondition.from(wmoCode: code), .heavySnow, "code \(code)")
        }
    }

    func testWMOMappingThunderstorm() {
        XCTAssertEqual(WeatherCondition.from(wmoCode: 95), .thunderstorm)
    }

    func testWMOMappingSevereThunderstorm() {
        for code in [96, 99] {
            XCTAssertEqual(WeatherCondition.from(wmoCode: code), .severeThunderstorm, "code \(code)")
        }
    }

    func testWMOUnknownCodeIsNil() {
        XCTAssertNil(WeatherCondition.from(wmoCode: 999))
        XCTAssertNil(WeatherCondition.from(wmoCode: -1))
    }

    func testIsPrecipitationAndDimsSky() {
        XCTAssertTrue(WeatherCondition.heavyRain.isPrecipitation)
        XCTAssertTrue(WeatherCondition.drizzle.isPrecipitation)
        XCTAssertFalse(WeatherCondition.cloudy.isPrecipitation)
        XCTAssertTrue(WeatherCondition.fog.dimsSky)
        XCTAssertTrue(WeatherCondition.snow.dimsSky)
        XCTAssertFalse(WeatherCondition.clear.dimsSky)
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
