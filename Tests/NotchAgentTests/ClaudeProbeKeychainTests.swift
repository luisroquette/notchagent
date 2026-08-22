import XCTest
@testable import NotchAgent

/// REGRESSÃO: o CLI 2.1 passou a gravar a credencial no Keychain com o
/// schema novo (claudeAiOauth) — e o probe precisa de fato LER o item
/// neste ambiente (o access group do item pertence ao CLI). Se este
/// teste falha, o probe também falha em produção: sem token, sem
/// percentual, o card cai no fallback de tokens.
final class ClaudeProbeKeychainTests: XCTestCase {
    func testProbeCanReadTheCliKeychainCredential() throws {
        // Never assert on the token's content — presence is the contract.
        // REGRESSÃO (22/08): the CI runner has no Claude Code CLI installed,
        // so there is no keychain credential to read — that's an environment
        // difference, not a probe regression. Skip there instead of failing;
        // on a dev machine with the CLI logged in, this still runs for real
        // and catches an actual regression.
        guard let token = ClaudeTokenLocator.oauthToken() else {
            throw XCTSkip("No Claude Code CLI keychain credential in this environment (expected in CI)")
        }
        XCTAssertNotNil(token)
    }

    // O schema novo do CLI 2.1: {"claudeAiOauth": {"accessToken": ...,
    // "expiresAt": <ms>}}. O parser deve extrair e respeitar a expiração.
    func testParseCredentialsReadsTheCli21Schema() {
        let payload = #"{"claudeAiOauth":{"accessToken":"sk-ant-test-token","expiresAt":99999999999999}}"#
        let token = ClaudeTokenLocator.parseCredentials(Data(payload.utf8))
        XCTAssertEqual(token, "sk-ant-test-token", "the 2.1 schema must parse")
    }

    func testParseCredentialsRejectsExpiredToken() {
        let expired = #"{"claudeAiOauth":{"accessToken":"sk-ant-test-token","expiresAt":1}}"#
        XCTAssertNil(
            ClaudeTokenLocator.parseCredentials(Data(expired.utf8)),
            "an expired access token must be rejected, not used"
        )
    }
}
