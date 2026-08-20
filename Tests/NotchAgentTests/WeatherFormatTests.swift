import XCTest
@testable import NotchAgent

final class WeatherFormatTests: XCTestCase {
    func testClockFormatsHHmmLocal() {
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 18
        components.hour = 9; components.minute = 5
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let date = calendar.date(from: components)!
        XCTAssertEqual(WeatherFormat.clock(date, timeZone: calendar.timeZone), "09:05")
    }

    func testTemperatureRoundsAndAppendsDegree() {
        XCTAssertEqual(WeatherFormat.temperature(24.3), "24°")
        XCTAssertEqual(WeatherFormat.temperature(24.6), "25°")
        XCTAssertEqual(WeatherFormat.temperature(-1.2), "-1°")
    }

    func testHighLowNeedsBothBounds() {
        XCTAssertEqual(WeatherFormat.highLow(max: 27.1, min: 12.4), "H: 27° L: 12°")
        XCTAssertNil(WeatherFormat.highLow(max: 27.1, min: nil))
        XCTAssertNil(WeatherFormat.highLow(max: nil, min: 12.4))
        XCTAssertNil(WeatherFormat.highLow(max: nil, min: nil))
    }

    func testConditionLabels() {
        XCTAssertEqual(WeatherCondition.clear.label, "Clear")
        XCTAssertEqual(WeatherCondition.partlyCloudy.label, "Partly cloudy")
        XCTAssertEqual(WeatherCondition.cloudy.label, "Cloudy")
        XCTAssertEqual(WeatherCondition.fog.label, "Fog")
        XCTAssertEqual(WeatherCondition.drizzle.label, "Drizzle")
        XCTAssertEqual(WeatherCondition.rain.label, "Rain")
        XCTAssertEqual(WeatherCondition.heavyRain.label, "Heavy rain")
        XCTAssertEqual(WeatherCondition.freezingRain.label, "Freezing rain")
        XCTAssertEqual(WeatherCondition.snow.label, "Snow")
        XCTAssertEqual(WeatherCondition.heavySnow.label, "Heavy snow")
        XCTAssertEqual(WeatherCondition.thunderstorm.label, "Thunderstorm")
        XCTAssertEqual(WeatherCondition.severeThunderstorm.label, "Severe thunderstorm")
        // Every condition renders a label — a new case without one fails
        // here instead of showing an empty header line.
        for condition in WeatherCondition.allCases {
            XCTAssertFalse(condition.label.isEmpty)
        }
    }

    // REFACTOR 19/08/2026: SF Symbols replaced by procedural 8-bit grids
    // (WeatherPixelArt) — every condition, day AND night, must render.
    func testPixelArtCoversEveryCondition() {
        for condition in WeatherCondition.allCases {
            for isDay in [true, false] {
                let grid = WeatherPixelArt.grid(for: condition, isDay: isDay)
                XCTAssertEqual(grid.count, 8, "\(condition) \(isDay) must be an 8-row grid")
                XCTAssertTrue(grid.allSatisfy { $0.count == 8 }, "\(condition) \(isDay) rows must be 8 wide")
                XCTAssertTrue(
                    grid.contains { row in row.contains(1) },
                    "\(condition) \(isDay) must draw at least one pixel"
                )
            }
        }
    }

    func testPixelArtDayNightDifferForSunAndCloud() {
        XCTAssertNotEqual(
            WeatherPixelArt.grid(for: .clear, isDay: true),
            WeatherPixelArt.grid(for: .clear, isDay: false),
            "clear sky shows a sun by day and a moon by night"
        )
        XCTAssertNotEqual(
            WeatherPixelArt.grid(for: .partlyCloudy, isDay: true),
            WeatherPixelArt.grid(for: .partlyCloudy, isDay: false),
            "partly cloudy keeps the day/night distinction"
        )
    }

    func testPixelArtConditionsAreDistinct() {
        // Every condition must be visually distinguishable — a collapsed
        // glyph (two conditions sharing one grid) fails here.
        var seen: Set<String> = []
        for condition in WeatherCondition.allCases {
            let key = WeatherPixelArt.grid(for: condition, isDay: true)
                .map { row in row.map(String.init).joined() }
                .joined(separator: "/")
            XCTAssertTrue(seen.insert(key).inserted, "\(condition) shares its glyph with another condition")
        }
    }
}
