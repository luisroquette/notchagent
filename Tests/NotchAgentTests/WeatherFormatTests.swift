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

    func testSymbolPerCondition() {
        XCTAssertEqual(WeatherFormat.symbol(for: .clear), "sun.max.fill")
        XCTAssertEqual(WeatherFormat.symbol(for: .partlyCloudy), "cloud.sun.fill")
        XCTAssertEqual(WeatherFormat.symbol(for: .cloudy), "cloud.fill")
        XCTAssertEqual(WeatherFormat.symbol(for: .fog), "cloud.fog.fill")
        XCTAssertEqual(WeatherFormat.symbol(for: .drizzle), "cloud.drizzle.fill")
        XCTAssertEqual(WeatherFormat.symbol(for: .rain), "cloud.rain.fill")
        XCTAssertEqual(WeatherFormat.symbol(for: .heavyRain), "cloud.heavyrain.fill")
        XCTAssertEqual(WeatherFormat.symbol(for: .freezingRain), "cloud.sleet.fill")
        XCTAssertEqual(WeatherFormat.symbol(for: .snow), "cloud.snow.fill")
        XCTAssertEqual(WeatherFormat.symbol(for: .heavySnow), "snowflake")
        XCTAssertEqual(WeatherFormat.symbol(for: .thunderstorm), "cloud.bolt.rain.fill")
        XCTAssertEqual(WeatherFormat.symbol(for: .severeThunderstorm), "cloud.bolt.fill")
    }
}
