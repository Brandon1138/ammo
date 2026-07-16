import Foundation

/// OpenAI Codex adapter.
///
/// API contract verified live 2026-07-16 (see SPEC.md §Codex). Codex no longer has a
/// 5-hour session limit — plans expose a weekly window only — so windows are labeled
/// by their advertised length, never by position.
public struct CodexProvider: UsageProvider {
    public let id = ProviderID.codex

    public static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    public static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    public static let authorizeURL = URL(string: "https://auth.openai.com/oauth/authorize")!
    /// Public client id used by the Codex CLI itself.
    public static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    public static let scopes = "openid profile email offline_access"
    /// The Codex CLI login flow redirects here; on iOS, Ammo runs a loopback listener
    /// on this port during ASWebAuthenticationSession (SPEC.md §Codex onboarding).
    public static let redirectURI = "http://localhost:1455/auth/callback"

    let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func fetchUsage(tokens: OAuthTokens) async throws -> UsageSnapshot {
        var headers = [
            "Authorization": "Bearer \(tokens.accessToken)",
            "User-Agent": "codex-cli",
        ]
        if let accountID = tokens.accountID {
            headers["ChatGPT-Account-Id"] = accountID
        }
        let data = try await transport.get(Self.usageURL, headers: headers)
        let response: Response
        do {
            response = try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw UsageError.malformedResponse("codex usage: \(error)")
        }
        return UsageSnapshot(provider: .codex,
                             plan: response.planType,
                             windows: Self.windows(from: response),
                             resetCreditsAvailable: response.rateLimitResetCredits?.availableCount)
    }

    public func refresh(tokens: OAuthTokens) async throws -> OAuthTokens {
        guard let refreshToken = tokens.refreshToken else {
            throw UsageError.notAuthenticated("codex: no refresh token")
        }
        let payload: [String: String] = [
            "client_id": Self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "openid profile email",
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await transport.post(Self.tokenURL,
                                            headers: ["Content-Type": "application/json"],
                                            body: body)
        let t: TokenResponse
        do {
            t = try Self.decoder.decode(TokenResponse.self, from: data)
        } catch {
            throw UsageError.malformedResponse("codex token: \(error)")
        }
        return OAuthTokens(accessToken: t.accessToken,
                           refreshToken: t.refreshToken ?? refreshToken,
                           expiresAt: t.expiresIn.map { Date(timeIntervalSinceNow: $0) },
                           accountID: tokens.accountID)
    }

    /// Builds the authorize URL for the loopback (localhost:1455) redirect flow.
    /// The two non-standard params mirror the Codex CLI's own login request.
    public static func authorizationRequestURL(pkce: PKCE) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: pkce.state),
        ]
        return components.url!
    }

    /// Exchanges the authorization code captured from the loopback redirect.
    /// The ChatGPT account id is not a token-response field — it rides inside the
    /// JWT claims (`https://api.openai.com/auth` → `chatgpt_account_id`).
    public func exchangeCode(_ code: String, verifier: String) async throws -> OAuthTokens {
        let body = formURLEncode([
            "grant_type": "authorization_code",
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "redirect_uri": Self.redirectURI,
            "client_id": Self.clientID,
            "code_verifier": verifier,
        ])
        let data = try await transport.post(Self.tokenURL,
                                            headers: ["Content-Type": "application/x-www-form-urlencoded"],
                                            body: body)
        let t: TokenResponse
        do {
            t = try Self.decoder.decode(TokenResponse.self, from: data)
        } catch {
            throw UsageError.malformedResponse("codex token: \(error)")
        }
        let accountID = Self.chatGPTAccountID(fromJWT: t.idToken)
            ?? Self.chatGPTAccountID(fromJWT: t.accessToken)
        return OAuthTokens(accessToken: t.accessToken,
                           refreshToken: t.refreshToken,
                           expiresAt: t.expiresIn.map { Date(timeIntervalSinceNow: $0) },
                           accountID: accountID)
    }

    /// Extracts `chatgpt_account_id` from a JWT's payload without verifying the
    /// signature (we only need the claim; the token is already trusted material).
    static func chatGPTAccountID(fromJWT jwt: String?) -> String? {
        guard let jwt else { return nil }
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let payload = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let auth = claims["https://api.openai.com/auth"] as? [String: Any]
        else { return nil }
        return auth["chatgpt_account_id"] as? String
    }

    // MARK: - Response mapping

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    struct Response: Decodable {
        struct Window: Decodable {
            let usedPercent: Double?
            let limitWindowSeconds: Double?
            let resetAt: Double?
        }
        struct RateLimit: Decodable {
            let primaryWindow: Window?
            let secondaryWindow: Window?
        }
        struct ResetCredits: Decodable { let availableCount: Int? }
        let planType: String?
        let rateLimit: RateLimit?
        let rateLimitResetCredits: ResetCredits?
    }

    struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double?
        let idToken: String?
    }

    static func windows(from response: Response) -> [LimitWindow] {
        [response.rateLimit?.primaryWindow, response.rateLimit?.secondaryWindow]
            .compactMap { $0 }
            .compactMap { window in
                guard let used = window.usedPercent else { return nil }
                let (kind, label) = classify(windowSeconds: window.limitWindowSeconds)
                return LimitWindow(kind: kind, label: label, usedPercent: used,
                                   resetsAt: window.resetAt.map { Date(timeIntervalSince1970: $0) })
            }
    }

    static func classify(windowSeconds: Double?) -> (WindowKind, String) {
        guard let seconds = windowSeconds else { return (.unknown, "Usage") }
        switch seconds {
        case ..<(24 * 3600): return (.session, "Session")
        case ..<(8 * 86400): return (.weekly, "Weekly")
        default: return (.monthly, "Monthly")
        }
    }
}
