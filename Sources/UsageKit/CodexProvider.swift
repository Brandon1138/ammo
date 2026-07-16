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
    /// Public client id used by the Codex CLI itself.
    public static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
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
