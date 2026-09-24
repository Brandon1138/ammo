import Foundation
import os

/// Anthropic / Claude Code adapter.
///
/// API contract verified live 2026-07-16 (see SPEC.md §Claude for the full contract
/// and re-derivation instructions). Uses the same OAuth surface as the Claude Code CLI.
public struct ClaudeProvider: UsageProvider {
    public let id = ProviderID.claude

    public static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage?cedar_ember=1")!
    public static let profileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    public static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    public static let authorizeURL = URL(string: "https://claude.ai/oauth/authorize")!
    /// Public client id used by the Claude Code CLI itself (PKCE, no secret).
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let scopes = "user:profile user:inference user:sessions:claude_code user:mcp_servers"
    /// The code=true flow redirects here; the page displays a code for the user to paste.
    public static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    static let betaHeader = "oauth-2025-04-20"
    static let cliSurfaceVersion = "2.1.280"
    private static let logger = Logger(subsystem: "com.brandon.ammo", category: "claude-usage")

    /// Surface identity approved for this usage request only.
    public static func usageHeaders(accessToken: String) -> [String: String] {
        [
            "Authorization": "Bearer \(accessToken)",
            "anthropic-beta": betaHeader,
            "User-Agent": "claude-cli/\(cliSurfaceVersion) (external, cli)",
            "x-app": "cli",
            "anthropic-client-platform": "macos",
        ]
    }

    let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func fetchUsage(tokens: OAuthTokens) async throws -> UsageSnapshot {
        let headers = [
            "Authorization": "Bearer \(tokens.accessToken)",
            "anthropic-beta": Self.betaHeader,
        ]
        async let usageData = transport.get(Self.usageURL,
                                            headers: Self.usageHeaders(accessToken: tokens.accessToken))
        // Plan metadata is useful but must not make the quota surface less
        // reliable. Claude Code treats this profile call as supplemental too.
        async let profileData: Data? = try? await transport.get(Self.profileURL, headers: headers)

        let data = try await usageData
        let response: Response
        do {
            response = try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw UsageError.malformedResponse("claude usage: \(error)")
        }
        if let reason = response.cedarEmber?.ineligibleReason, reason != "no_grant" {
            Self.logger.info("cedar_ember ineligible_reason: \(reason, privacy: .public)")
        }
        let profileBytes = await profileData
        let profile = profileBytes.flatMap(Self.profile(from:))
        return UsageSnapshot(provider: .claude,
                             plan: profile.flatMap(Self.plan(from:)),
                             windows: Self.windows(from: response),
                             bankedResets: Self.bankedResets(from: response),
                             onDemand: Self.onDemand(from: response))
    }

    public func refresh(tokens: OAuthTokens) async throws -> OAuthTokens {
        guard let refreshToken = tokens.refreshToken else {
            throw UsageError.notAuthenticated("claude: no refresh token")
        }
        let body = formURLEncode([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ])
        let data = try await transport.post(Self.tokenURL,
                                            headers: ["Content-Type": "application/x-www-form-urlencoded"],
                                            body: body)
        return try Self.tokens(fromTokenResponse: data, fallbackRefresh: refreshToken)
    }

    /// Builds the `code=true` authorize URL: the callback page renders the auth
    /// code on-screen for the user to copy — no redirect capture needed on iOS.
    public static func authorizationRequestURL(pkce: PKCE) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
        ]
        return components.url!
    }

    /// Exchanges a pasted authorization code (code=true flow) for tokens.
    /// `code` is what the user pasted; anything after `#` is a state fragment.
    public func exchangeCode(_ code: String, verifier: String, state: String) async throws -> OAuthTokens {
        let cleaned = String(code.split(separator: "#").first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = formURLEncode([
            "grant_type": "authorization_code",
            "code": cleaned,
            "redirect_uri": Self.redirectURI,
            "client_id": Self.clientID,
            "code_verifier": verifier,
            "state": state,
        ])
        let data = try await transport.post(Self.tokenURL,
                                            headers: ["Content-Type": "application/x-www-form-urlencoded"],
                                            body: body)
        return try Self.tokens(fromTokenResponse: data, fallbackRefresh: nil)
    }

    // MARK: - Response mapping

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    struct Response: Decodable {
        struct CedarEmber: Decodable {
            struct Grant: Decodable {
                let id: String?
                let resetsLeft: Int?
                let endsAt: String?
                let paused: Bool?
                let usableNow: Bool?
                let useRequiresLimit: Bool?
            }

            struct LossyGrant: Decodable {
                let value: Grant?
                init(from decoder: any Decoder) throws {
                    value = try? Grant(from: decoder)
                }
            }

            let eligible: Bool?
            let ineligibleReason: String?
            let grants: [Grant]

            init(from decoder: any Decoder) throws {
                guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                    eligible = nil
                    ineligibleReason = nil
                    grants = []
                    return
                }
                eligible = try? container.decodeIfPresent(Bool.self, forKey: .eligible)
                ineligibleReason = try? container.decodeIfPresent(String.self, forKey: .ineligibleReason)
                grants = (try? container.decodeIfPresent([LossyGrant].self, forKey: .grants))?
                    .compactMap(\.value) ?? []
            }

            private enum CodingKeys: String, CodingKey { case eligible, ineligibleReason, grants }
        }

        struct Bucket: Decodable {
            let utilization: Double?
            let resetsAt: String?
        }
        struct Limit: Decodable {
            struct Scope: Decodable {
                struct Model: Decodable { let displayName: String? }
                let model: Model?
            }
            let kind: String?
            let percent: Double?
            let resetsAt: String?
            let scope: Scope?
        }
        struct ExtraUsage: Decodable {
            let isEnabled: Bool?
            /// Anthropic reports monetary values in minor currency units.
            let monthlyLimit: Double?
            let usedCredits: Double?
            let utilization: Double?
            let currency: String?
        }
        let fiveHour: Bucket?
        let sevenDay: Bucket?
        let limits: [Limit]?
        let extraUsage: ExtraUsage?
        let cedarEmber: CedarEmber?
    }

    struct Profile: Decodable {
        struct Organization: Decodable {
            let subscriptionType: String?
            let organizationType: String?
            let rateLimitTier: String?
            let seatTier: String?
        }

        let subscriptionType: String?
        let organizationType: String?
        let rateLimitTier: String?
        let seatTier: String?
        let organization: Organization?
        let organizations: [Organization]?
    }

    struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double?
    }

    static func tokens(fromTokenResponse data: Data, fallbackRefresh: String?) throws -> OAuthTokens {
        let t: TokenResponse
        do {
            t = try decoder.decode(TokenResponse.self, from: data)
        } catch {
            throw UsageError.malformedResponse("claude token: \(error)")
        }
        return OAuthTokens(accessToken: t.accessToken,
                           refreshToken: t.refreshToken ?? fallbackRefresh,
                           expiresAt: t.expiresIn.map { Date(timeIntervalSinceNow: $0) })
    }

    static func profile(from data: Data) -> Profile? {
        try? decoder.decode(Profile.self, from: data)
    }

    static func plan(from profile: Profile) -> String? {
        let organization = profile.organization ?? profile.organizations?.first
        let candidates = [
            profile.subscriptionType,
            organization?.subscriptionType,
            organization?.organizationType,
            profile.organizationType,
            organization?.rateLimitTier,
            profile.rateLimitTier,
            organization?.seatTier,
            profile.seatTier,
        ]
        return candidates.compactMap(canonicalPlan).first
    }

    private static func canonicalPlan(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let words = raw.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        for plan in ["ultra", "enterprise", "team", "max", "pro"] where words.contains(plan) {
            return plan
        }
        return nil
    }

    static func windows(from response: Response) -> [LimitWindow] {
        // The limits[] array is the normalized source of truth; five_hour/seven_day
        // duplicate its session/weekly entries and serve as a fallback only.
        if let limits = response.limits, !limits.isEmpty {
            return limits.compactMap { limit in
                guard let percent = limit.percent else { return nil }
                let (kind, label): (WindowKind, String)
                switch limit.kind {
                case "session": (kind, label) = (.session, "Session")
                case "weekly_all": (kind, label) = (.weekly, "Weekly")
                case "weekly_scoped":
                    (kind, label) = (.modelScoped, limit.scope?.model?.displayName ?? "Model")
                default: (kind, label) = (.unknown, limit.kind ?? "Other")
                }
                return LimitWindow(kind: kind, label: label, usedPercent: percent,
                                   resetsAt: ISO8601.parse(limit.resetsAt))
            }
        }
        var windows: [LimitWindow] = []
        if let session = response.fiveHour, let used = session.utilization {
            windows.append(LimitWindow(kind: .session, label: "Session", usedPercent: used,
                                       resetsAt: ISO8601.parse(session.resetsAt)))
        }
        if let weekly = response.sevenDay, let used = weekly.utilization {
            windows.append(LimitWindow(kind: .weekly, label: "Weekly", usedPercent: used,
                                       resetsAt: ISO8601.parse(weekly.resetsAt)))
        }
        return windows
    }

    static func onDemand(from response: Response) -> [OnDemandUsage]? {
        guard let extra = response.extraUsage else { return nil }
        let limit = extra.monthlyLimit.map { max(0, $0) / 100 }
        let used = extra.usedCredits.map { max(0, $0) / 100 }
        return [OnDemandUsage(
            id: "claude-extra-usage",
            label: "Extra usage",
            kind: .spendingLimit,
            scope: .personal,
            isEnabled: extra.isEnabled,
            currencyCode: extra.currency ?? "USD",
            used: used,
            limit: limit,
            remaining: limit.map { max(0, $0 - (used ?? 0)) },
            usedPercent: extra.utilization
        )]
    }

    static func bankedResets(from response: Response) -> BankedResets? {
        guard let cedar = response.cedarEmber, cedar.eligible == true else { return nil }
        let grants = cedar.grants.filter {
            $0.paused != true && ($0.resetsLeft ?? 0) > 0
        }
        let count = grants.reduce(0) { $0 + ($1.resetsLeft ?? 0) }
        guard count > 0 else { return BankedResets(count: 0, expiresAt: nil, usableNow: false) }
        return BankedResets(
            count: count,
            expiresAt: grants.compactMap { ISO8601.parse($0.endsAt) }.min(),
            usableNow: grants.contains { $0.usableNow == true }
        )
    }
}
