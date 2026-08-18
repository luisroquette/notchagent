import XCTest
@testable import NotchAgent

final class AppSettingsWeatherTests: XCTestCase {
    private func decode(_ json: String) -> AppSettings? {
        try? JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    func testWeatherEnabledDefaultsToTrueOnLegacyPayload() {
        let settings = decode("{\"themeMode\":\"auto\"}")
        XCTAssertEqual(settings?.weatherEnabled, true, "legacy payload without the key must enable weather")
    }

    func testWeatherFieldsDecodeWhenPresent() {
        let settings = decode("""
        {"weatherEnabled":false,"weatherCity":"Recife","weatherLat":-8.05,"weatherLon":-34.9,"weatherCityResolved":"Recife, BR"}
        """)
        XCTAssertEqual(settings?.weatherEnabled, false)
        XCTAssertEqual(settings?.weatherCity, "Recife")
        XCTAssertEqual(settings?.weatherLat, -8.05)
        XCTAssertEqual(settings?.weatherLon, -34.9)
        XCTAssertEqual(settings?.weatherCityResolved, "Recife, BR")
    }

    func testWeatherOptionalFieldsDefaultToNil() {
        let settings = decode("{}")
        XCTAssertNil(settings?.weatherCity)
        XCTAssertNil(settings?.weatherLat)
        XCTAssertNil(settings?.weatherLon)
        XCTAssertNil(settings?.weatherCityResolved)
    }
}
