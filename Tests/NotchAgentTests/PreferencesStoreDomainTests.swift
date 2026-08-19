import XCTest
@testable import NotchAgent

/// REGRESSÃO: o `swift run` não tem bundle id, então UserDefaults.standard
/// caía no domínio do executável — toda instância de teste ignorava as
/// prefs do app instalado (probe off, sem consentimento) enquanto o app
/// instalado funcionava. O defaultStore deve ser o MESMO domínio
/// (br.com.lfrprojects.notchagent) nos dois mundos de empacotamento.
@MainActor
final class PreferencesStoreDomainTests: XCTestCase {
    func testDefaultStoreSharesTheAppSuiteDomain() {
        let suite = UserDefaults(suiteName: "br.com.lfrprojects.notchagent")
        XCTAssertNotNil(suite, "the suite domain must exist")
        guard let suite else { return }
        suite.set("domain-probe-value", forKey: "na_domain_test_key")
        let fromDefaultStore = PreferencesStore.defaultStore.string(forKey: "na_domain_test_key")
        XCTAssertEqual(
            fromDefaultStore,
            "domain-probe-value",
            "defaultStore must read the same domain the installed app's standard defaults use"
        )
        suite.removeObject(forKey: "na_domain_test_key")
    }
}
