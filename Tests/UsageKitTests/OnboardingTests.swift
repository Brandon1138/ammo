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

/// Replays one scripted response per call and keeps every request, so a test can
/// assert what credential the *next* call carried.
private final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Data, Int)]
    private var recorded: [URLRequest] = []

    init(responses: [(Data, Int)]) {
        self.responses = responses
    }

    convenience init(json: [Any]) {
        self.init(responses: json.map {
            // swiftlint:disable:next force_try
            (try! JSONSerialization.data(withJSONObject: $0), 200)
        })
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    func body(at index: Int) throws -> [String: Any] {
        let bodies = requests.compactMap(\.httpBody)
        guard index < bodies.count,
              let object = try JSONSerialization.jsonObject(with: bodies[index]) as? [String: Any]
        else {
            throw StubError.noBody
        }
        return object
    }

    enum StubError: Error { case exhausted, noBody }

    func request(_ req: URLRequest) async throws -> (Data, Int) {
        try lock.withLock {
            recorded.append(req)
            guard !responses.isEmpty else { throw StubError.exhausted }
            return responses.removeFirst()
        }
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

/// Cursor rotates the refresh credential on every token call, and the value the
/// next call must present depends on which fields came back. Getting this wrong
/// logs the account out silently, so pin the whole response matrix.
@Suite struct CursorRefreshTests {
    private func fakeJWT(subject: String = "auth0|user_ABC",
                         expiry: Double = 1_800_000_000) -> String {
        let header = Data(#"{"alg":"none"}"#.utf8).base64URLEncoded
        // swiftlint:disable:next force_try
        let body = try! JSONSerialization.data(withJSONObject: ["sub": subject, "exp": expiry])
        return "\(header).\(body.base64URLEncoded).sig"
    }

    @Test("A rotated refresh_token replaces the one we sent")
    func adoptsRotatedRefreshToken() async throws {
        let jwt = fakeJWT()
        let transport = ScriptedTransport(json: [
            ["accessToken": jwt, "refreshToken": "refresh-2"],
        ])
        let refreshed = try await CursorProvider(transport: transport).refresh(
            tokens: OAuthTokens(accessToken: "old-access", refreshToken: "refresh-1"))

        #expect(refreshed.accessToken == jwt)
        #expect(refreshed.refreshToken == "refresh-2")
        #expect(refreshed.accountID == "user_ABC")
        #expect(refreshed.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(try transport.body(at: 0)["refresh_token"] as? String == "refresh-1")
        #expect(try transport.body(at: 0)["grant_type"] as? String == "refresh_token")
        #expect(try transport.body(at: 0)["client_id"] as? String == CursorProvider.clientID)
    }

    @Test("Omitting refresh_token promotes the new access token to the refresh credential")
    func fallsBackToAccessTokenWhenRotationIsOmitted() async throws {
        let jwt = fakeJWT()
        let transport = ScriptedTransport(json: [["accessToken": jwt]])
        let refreshed = try await CursorProvider(transport: transport).refresh(
            tokens: OAuthTokens(accessToken: "old-access", refreshToken: "refresh-1"))

        #expect(refreshed.refreshToken == jwt)
    }

    @Test("Each refresh presents the credential the previous one returned")
    func rotationChainsAcrossSuccessiveRefreshes() async throws {
        let first = fakeJWT(expiry: 1_800_000_000)
        let second = fakeJWT(expiry: 1_900_000_000)
        let transport = ScriptedTransport(json: [
            ["accessToken": first, "refreshToken": "refresh-2"],
            // No rotation this time: the chain has to carry `first` forward.
            ["accessToken": second],
        ])
        let provider = CursorProvider(transport: transport)

        let once = try await provider.refresh(
            tokens: OAuthTokens(accessToken: "old-access", refreshToken: "refresh-1"))
        let twice = try await provider.refresh(tokens: once)
        let thrice = OAuthTokens(accessToken: twice.accessToken,
                                 refreshToken: twice.refreshToken,
                                 expiresAt: twice.expiresAt,
                                 accountID: twice.accountID)

        #expect(try transport.body(at: 0)["refresh_token"] as? String == "refresh-1")
        #expect(try transport.body(at: 1)["refresh_token"] as? String == "refresh-2")
        #expect(twice.refreshToken == second)
        #expect(twice.expiresAt == Date(timeIntervalSince1970: 1_900_000_000))
        // What we would persist round-trips through the Keychain encoding
        // unchanged; a dropped rotation here is what silently logs the user out.
        let encoded = try JSONEncoder().encode(thrice)
        let decoded = try JSONDecoder().decode(OAuthTokens.self, from: encoded)
        #expect(decoded.refreshToken == second)
        #expect(decoded.accessToken == second)
        #expect(decoded.expiresAt == twice.expiresAt)
        #expect(decoded.accountID == "user_ABC")
    }

    @Test("shouldLogout is surfaced as an authentication failure, not a rotation")
    func serverRequestedLogoutStopsTheRotation() async {
        let transport = ScriptedTransport(json: [
            ["accessToken": "unused", "refreshToken": "refresh-2", "shouldLogout": true],
        ])

        do {
            _ = try await CursorProvider(transport: transport).refresh(
                tokens: OAuthTokens(accessToken: "old-access", refreshToken: "refresh-1"))
            Issue.record("Expected the server logout request to fail the refresh")
        } catch let error as UsageError {
            guard case .notAuthenticated = error else {
                Issue.record("Expected notAuthenticated, received \(error)")
                return
            }
            #expect(UsageFailureClassifier.classify(error) == .authentication)
        } catch {
            Issue.record("Expected UsageError, received \(error)")
        }
    }

    @Test("shouldLogout: false is an ordinary rotation")
    func explicitFalseLogoutStillRotates() async throws {
        let jwt = fakeJWT()
        let transport = ScriptedTransport(json: [
            ["accessToken": jwt, "refreshToken": "refresh-2", "shouldLogout": false],
        ])
        let refreshed = try await CursorProvider(transport: transport).refresh(
            tokens: OAuthTokens(accessToken: "old-access", refreshToken: "refresh-1"))

        #expect(refreshed.refreshToken == "refresh-2")
    }

    @Test("A refresh without a stored refresh token never reaches the network")
    func missingRefreshTokenFailsBeforeRequesting() async {
        let transport = ScriptedTransport(responses: [])

        do {
            _ = try await CursorProvider(transport: transport).refresh(
                tokens: OAuthTokens(accessToken: "old-access"))
            Issue.record("Expected a notAuthenticated failure")
        } catch let error as UsageError {
            guard case .notAuthenticated = error else {
                Issue.record("Expected notAuthenticated, received \(error)")
                return
            }
        } catch {
            Issue.record("Expected UsageError, received \(error)")
        }
        #expect(transport.requests.isEmpty)
    }

    @Test("A malformed token response is reported as malformed, not as new tokens")
    func malformedRefreshResponseIsRejected() async {
        let transport = ScriptedTransport(responses: [
            (Data(#"{"refreshToken":"refresh-2"}"#.utf8), 200),
        ])

        do {
            _ = try await CursorProvider(transport: transport).refresh(
                tokens: OAuthTokens(accessToken: "old-access", refreshToken: "refresh-1"))
            Issue.record("Expected an explicit malformed-response failure")
        } catch let error as UsageError {
            guard case .malformedResponse = error else {
                Issue.record("Expected malformedResponse, received \(error)")
                return
            }
        } catch {
            Issue.record("Expected UsageError, received \(error)")
        }
    }

    @Test("An HTTP failure keeps its status instead of decoding the error body")
    func httpFailureIsNotDecodedAsTokens() async {
        let transport = ScriptedTransport(responses: [
            (Data(#"{"error":"invalid_grant"}"#.utf8), 401),
        ])

        do {
            _ = try await CursorProvider(transport: transport).refresh(
                tokens: OAuthTokens(accessToken: "old-access", refreshToken: "refresh-1"))
            Issue.record("Expected an HTTP failure")
        } catch let error as UsageError {
            guard case .http(let status, _) = error else {
                Issue.record("Expected http, received \(error)")
                return
            }
            #expect(status == 401)
        } catch {
            Issue.record("Expected UsageError, received \(error)")
        }
    }

    @Test("An opaque access token still rotates, just without expiry or account id")
    func nonJWTAccessTokenRotatesWithoutClaims() async throws {
        let transport = ScriptedTransport(json: [
            ["accessToken": "opaque-access", "refreshToken": "refresh-2"],
        ])
        let refreshed = try await CursorProvider(transport: transport).refresh(
            tokens: OAuthTokens(accessToken: "old-access", refreshToken: "refresh-1"))

        #expect(refreshed.accessToken == "opaque-access")
        #expect(refreshed.refreshToken == "refresh-2")
        #expect(refreshed.expiresAt == nil)
        #expect(refreshed.accountID == nil)
    }
}
