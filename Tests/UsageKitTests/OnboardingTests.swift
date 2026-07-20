import Foundation
import Testing
@testable import UsageKit

private struct StubTransport: HTTPTransport {
    let data: Data
    let status: Int

    func request(_ req: URLRequest) async throws -> (Data, Int) {
        (data, status)
    }
}

@Suite struct PKCETests {
    @Test func challengeMatchesRFC7636Vector() {
        // Appendix B of RFC 7636.
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "s")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generatedValuesAreURLSafeAndLongEnough() {
        let pkce = PKCE()
        // RFC 7636 requires a 43–128 char verifier from the unreserved set.
        #expect(pkce.verifier.count >= 43 && pkce.verifier.count <= 128)
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        #expect(pkce.verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
        #expect(PKCE().verifier != pkce.verifier)
    }
}

@Suite struct AuthorizeURLTests {
    @Test func claudeAuthorizeURLCarriesPasteFlowParams() throws {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "the-state")
        let url = ClaudeProvider.authorizationRequestURL(pkce: pkce)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        #expect(url.host() == "claude.ai")
        #expect(value("code") == "true")
        #expect(value("client_id") == ClaudeProvider.clientID)
        #expect(value("redirect_uri") == ClaudeProvider.redirectURI)
        #expect(value("code_challenge") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(value("code_challenge_method") == "S256")
        #expect(value("state") == "the-state")
        #expect(value("scope") == ClaudeProvider.scopes)
    }

    @Test func codexAuthorizeURLTargetsLoopbackRedirect() throws {
        let url = CodexProvider.authorizationRequestURL(pkce: PKCE())
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        #expect(url.host() == "auth.openai.com")
        #expect(value("redirect_uri") == "http://localhost:1455/auth/callback")
        #expect(value("client_id") == CodexProvider.clientID)
        #expect(value("code_challenge_method") == "S256")
    }

    @Test func cursorAuthorizeURLCarriesPollingBinding() throws {
        let uuid = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!
        let url = CursorProvider.authorizationRequestURL(pkce: PKCE(), uuid: uuid)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        #expect(url.host() == "cursor.com")
        #expect(value("uuid") == "12345678-1234-1234-1234-123456789abc")
        #expect(value("challenge")?.isEmpty == false)
        #expect(value("mode") == "login")
        #expect(value("supportsSelectedTeamLogin") == "true")
        #expect(value("redirectTarget") == nil)
    }
}

@Suite struct CodexJWTTests {
    private func fakeJWT(payload: [String: Any]) -> String {
        let header = Data(#"{"alg":"none"}"#.utf8).base64URLEncoded
        let body = try! JSONSerialization.data(withJSONObject: payload) // swiftlint:disable:this force_try
        return "\(header).\(body.base64URLEncoded).sig"
    }

    @Test func extractsChatGPTAccountIDFromClaims() {
        let jwt = fakeJWT(payload: [
            "sub": "user-123",
            "https://api.openai.com/auth": ["chatgpt_account_id": "acct-abc-123"],
        ])
        #expect(CodexProvider.chatGPTAccountID(fromJWT: jwt) == "acct-abc-123")
    }

    @Test func toleratesMissingClaimAndGarbage() {
        #expect(CodexProvider.chatGPTAccountID(fromJWT: nil) == nil)
        #expect(CodexProvider.chatGPTAccountID(fromJWT: "not-a-jwt") == nil)
        #expect(CodexProvider.chatGPTAccountID(fromJWT: fakeJWT(payload: ["sub": "x"])) == nil)
    }
}

@Suite struct CursorAuthTests {
    private func fakeJWT(payload: [String: Any]) -> String {
        let header = Data(#"{"alg":"none"}"#.utf8).base64URLEncoded
        let body = try! JSONSerialization.data(withJSONObject: payload) // swiftlint:disable:this force_try
        return "\(header).\(body.base64URLEncoded).sig"
    }

    @Test func extractsCookieUserAndExpiration() throws {
        let jwt = fakeJWT(payload: ["sub": "auth0|user_ABC-123", "exp": 1_800_000_000])
        let tokens = OAuthTokens(accessToken: jwt)

        #expect(CursorProvider.userID(fromJWT: jwt) == "user_ABC-123")
        #expect(CursorProvider.expiration(fromJWT: jwt) == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(try CursorProvider.cookieHeader(tokens: tokens)
            == "WorkosCursorSessionToken=user_ABC-123%3A%3A\(jwt)")
    }

    @Test func pendingPollReturnsNil() async throws {
        let provider = CursorProvider(transport: StubTransport(data: Data(), status: 404))
        let tokens = try await provider.pollForTokens(uuid: UUID(), verifier: "verifier")
        #expect(tokens == nil)
    }

    @Test func completedPollReturnsRefreshableTokens() async throws {
        let jwt = fakeJWT(payload: ["sub": "auth0|user_ABC", "exp": 1_800_000_000])
        let response = try JSONSerialization.data(withJSONObject: [
            "accessToken": jwt,
            "refreshToken": "refresh-token",
        ])
        let provider = CursorProvider(transport: StubTransport(data: response, status: 200))
        let polled = try await provider.pollForTokens(uuid: UUID(), verifier: "verifier")
        let tokens = try #require(polled)

        #expect(tokens.accessToken == jwt)
        #expect(tokens.refreshToken == "refresh-token")
        #expect(tokens.accountID == "user_ABC")
        #expect(tokens.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
    }
}
