import XCTest
@testable import NotchAgent

final class AppSettingsDelightTests: XCTestCase {
    private func decode(_ json: String) -> AppSettings? {
        try? JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    func testDelightEnabledDefaultsToTrueOnLegacyPayload() {
        let settings = decode("{\"themeMode\":\"auto\"}")
        XCTAssertEqual(settings?.delightEnabled, true, "legacy payload without the key must enable delight")
    }

    func testDelightEnabledDecodesWhenPresent() {
        let settings = decode("{\"delightEnabled\":false}")
        XCTAssertEqual(settings?.delightEnabled, false)
    }
}
