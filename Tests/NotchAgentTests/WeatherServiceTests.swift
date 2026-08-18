import XCTest
@testable import NotchAgent

final class WeatherServiceTests: XCTestCase {
    private let openMeteoPayload = Data("""
    {"timezone":"America/Sao_Paulo",
     "current":{"time":"2026-08-18T19:00","temperature_2m":24.3,"weather_code":65,"is_day":0,"wind_speed_10m":22.5},
     "daily":{"sunrise":["2026-08-18T06:20"],"sunset":["2026-08-18T17:55"]}}
    """.utf8)

    private let geocodingPayload = Data("""
    {"results":[{"name":"São Paulo","latitude":-23.55,"longitude":-46.63,"country":"BR","admin1":"São Paulo"}]}
    """.utf8)

    private let ipPayload = Data("""
    {"success":true,"latitude":-23.55,"longitude":-46.63,"city":"São Paulo","country":"Brazil","country_code":"BR"}
    """.utf8)

    func testOpenMeteoParseHappyPath() {
        let now = Date(timeIntervalSince1970: 1_756_000_000)
        let snap = WeatherService.snapshot(fromOpenMeteo: openMeteoPayload, city: "São Paulo, BR", now: now)
        XCTAssertEqual(snap?.condition, .heavyRain)
        XCTAssertEqual(snap?.temperatureC, 24.3)
        XCTAssertEqual(snap?.isDay, false)
        XCTAssertEqual(snap?.city, "São Paulo, BR")
        XCTAssertEqual(snap?.capturedAt, now)
        XCTAssertEqual(snap?.windSpeedKmh, 22.5)
        XCTAssertNotNil(snap?.sunrise, "sunrise must parse in the reported timezone")
        XCTAssertNotNil(snap?.sunset)
    }

    func testDayDateParsesInReportedTimezone() {
        let tz = TimeZone(identifier: "America/Sao_Paulo")!
        let date = WeatherService.dayDate("2026-08-18T06:20", timeZone: tz)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let hour = date.map { calendar.component(.hour, from: $0) }
        XCTAssertEqual(hour, 6)
    }

    func testOpenMeteoParseUnknownCodeIsNil() {
        let payload = Data("""
        {"current":{"time":"2026-08-18T19:00","temperature_2m":24.3,"weather_code":999,"is_day":1}}
        """.utf8)
        XCTAssertNil(WeatherService.snapshot(fromOpenMeteo: payload, city: "X", now: .now))
    }

    func testOpenMeteoParseMalformedIsNil() {
        XCTAssertNil(WeatherService.snapshot(fromOpenMeteo: Data("not json".utf8), city: "X", now: .now))
        XCTAssertNil(WeatherService.snapshot(fromOpenMeteo: Data("{}".utf8), city: "X", now: .now))
    }

    func testGeocodingParseHappyPath() {
        guard let place = WeatherService.place(fromGeocoding: geocodingPayload) else {
            return XCTFail("expected a place")
        }
        XCTAssertEqual(place.0, -23.55, accuracy: 0.001)
        XCTAssertEqual(place.1, -46.63, accuracy: 0.001)
        XCTAssertEqual(place.2, "São Paulo, BR")
    }

    func testGeocodingParseEmptyResultsIsNil() {
        XCTAssertNil(WeatherService.place(fromGeocoding: Data("{\"results\":[]}".utf8)))
        XCTAssertNil(WeatherService.place(fromGeocoding: Data("not json".utf8)))
    }

    func testIPParseHappyPath() {
        guard let place = WeatherService.place(fromIP: ipPayload) else {
            return XCTFail("expected a place")
        }
        XCTAssertEqual(place.0, -23.55, accuracy: 0.001)
        XCTAssertEqual(place.1, -46.63, accuracy: 0.001)
        XCTAssertEqual(place.2, "São Paulo, BR")
    }

    func testIPParseFailureIsNil() {
        XCTAssertNil(WeatherService.place(fromIP: Data("{\"success\":false}".utf8)))
        XCTAssertNil(WeatherService.place(fromIP: Data("not json".utf8)))
    }
}
