import Foundation
import Testing

@testable import UsageKit

/// Builds an unsigned JWT whose payload carries `claims`. Identity derivation
/// reads claims out of material the provider already issued; it never verifies
/// the signature, so a structurally valid token is enough here.
private func jwt(claims: [String: Any]) -> String {
    let payload = try! JSONSerialization.data(withJSONObject: claims)
    let encoded = payload.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "header.\(encoded).signature"
}

private let codexAccountID = "acct_9f2c1b7e-4d55-4d1a-9d0d-6a3b0c7f1e42"

private func codexTokens(accountID: String? = codexAccountID) -> OAuthTokens {
    OAuthTokens(
        accessToken: jwt(claims: [
            "https://api.openai.com/auth": ["chatgpt_account_id": codexAccountID],
        ]),
        refreshToken: "refresh",
        accountID: accountID)
}

private func cursorTokens(userID: String = "user_01JABCDEF") -> OAuthTokens {
    OAuthTokens(accessToken: jwt(claims: ["sub": "auth0|\(userID)", "exp": 4_102_444_800]))
}

@Suite("Account natural identity")
struct AccountIdentityTests {

    // MARK: - Per-provider derivation

    @Test("Codex identity comes from the ChatGPT account id the auth response carried")
    func codexIdentityUsesChatGPTAccountID() throws {
        let identity = try #require(
            AccountIdentityResolver.identity(provider: .codex, tokens: codexTokens()))

        #expect(identity.provider == .codex)
        #expect(identity.subjectDigest
            == AccountIdentity.digest(provider: .codex, subject: codexAccountID))
    }

    @Test("A Codex credential with no stored account id falls back to its own JWT claim")
    func codexIdentityFallsBackToAccessTokenClaim() {
        #expect(AccountIdentityResolver.identity(provider: .codex,
                                                 tokens: codexTokens(accountID: nil))
            == AccountIdentityResolver.identity(provider: .codex, tokens: codexTokens()))
    }

    @Test("Cursor identity comes from the user id its access token already exposes")
    func cursorIdentityUsesAccessTokenSubject() throws {
        let identity = try #require(
            AccountIdentityResolver.identity(provider: .cursor, tokens: cursorTokens()))

        #expect(identity.provider == .cursor)
        #expect(identity.subjectDigest
            == AccountIdentity.digest(provider: .cursor, subject: "user_01JABCDEF"))
    }

    // MARK: - Matching

    @Test("A later credential for the same provider account produces the same key")
    func rotatedCredentialKeepsItsIdentity() {
        let first = AccountIdentityResolver.identity(provider: .codex, tokens: codexTokens())
        // A fresh sign-in issues entirely new token material for the same person.
        let second = AccountIdentityResolver.identity(
            provider: .codex,
            tokens: OAuthTokens(accessToken: "totally-different-token",
                                refreshToken: "new-refresh",
                                accountID: codexAccountID))

        #expect(first == second)
        #expect(AccountIdentityResolver.matches(first, second))
    }

    @Test("Two different provider accounts never share a key")
    func differentSubjectsDoNotMatch() {
        let mine = AccountIdentityResolver.identity(provider: .codex, tokens: codexTokens())
        let theirs = AccountIdentityResolver.identity(
            provider: .codex, tokens: codexTokens(accountID: "acct_someone-else"))

        #expect(!AccountIdentityResolver.matches(mine, theirs))
    }

    @Test("The same opaque subject at two providers stays two identities")
    func identityIsDomainSeparatedByProvider() {
        #expect(AccountIdentity(provider: .codex, subject: "shared-subject")
            != AccountIdentity(provider: .cursor, subject: "shared-subject"))
    }

    @Test("An unknown key matches nothing, including another unknown key")
    func missingIdentityNeverMatches() {
        let known = AccountIdentityResolver.identity(provider: .codex, tokens: codexTokens())

        #expect(!AccountIdentityResolver.matches(nil, nil))
        #expect(!AccountIdentityResolver.matches(known, nil))
        #expect(!AccountIdentityResolver.matches(nil, known))
    }

    // MARK: - Graceful degradation

    @Test("Providers whose sign-in exposes no user identity derive no key")
    func providersWithoutSubjectsDegradeToNoIdentity() {
        // Claude's token exchange returns tokens only; OpenRouter imports a key
        // and performs no auth call at all. Neither may be given an invented key.
        #expect(AccountIdentityResolver.identity(
            provider: .claude,
            tokens: OAuthTokens(accessToken: "sk-ant-oat01-abc",
                                refreshToken: "sk-ant-ort01-def")) == nil)
        #expect(AccountIdentityResolver.identity(
            provider: .openRouter,
            tokens: OAuthTokens(accessToken: "sk-or-v1-abc")) == nil)
    }

    @Test("Unusable subjects are treated as absent rather than keyed on")
    func blankAndUnparsableSubjectsYieldNoIdentity() {
        #expect(AccountIdentityResolver.identity(
            provider: .codex,
            tokens: OAuthTokens(accessToken: "not-a-jwt", accountID: "   ")) == nil)
        #expect(AccountIdentityResolver.identity(
            provider: .cursor,
            tokens: OAuthTokens(accessToken: "not-a-jwt")) == nil)
    }

    // MARK: - Storage shape

    @Test("The stored key is a digest, never the raw provider subject")
    func identityStoresOnlyADigest() throws {
        let identity = AccountIdentity(provider: .claude, subject: "person@example.com")
        let json = String(decoding: try JSONEncoder().encode(identity), as: UTF8.self)

        #expect(!json.contains("person@example.com"))
        #expect(identity.subjectDigest.count == 64)
        #expect(identity.subjectDigest.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("A persisted key decodes back to the same value")
    func identityRoundTripsThroughJSON() throws {
        let identity = AccountIdentity(provider: .cursor, subject: "user_01JABCDEF")
        let decoded = try JSONDecoder().decode(
            AccountIdentity.self, from: try JSONEncoder().encode(identity))

        #expect(decoded == identity)
    }
}
