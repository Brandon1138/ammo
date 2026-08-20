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
        let windows = Self.windows(from: response)
        let onDemand = Self.onDemand(from: response)
        guard !windows.isEmpty || onDemand?.isEmpty == false else {
            throw UsageError.malformedResponse(
                "codex usage: response contained no included or on-demand usage")
        }
        return UsageSnapshot(provider: .codex,
                             plan: response.planType,
                             windows: windows,
                             resetCreditsAvailable: response.rateLimitResetCredits?.availableCount,
                             onDemand: onDemand)
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
            let individualLimit: SpendControl?
        }
        struct Credits: Decodable {
            let hasCredits: Bool?
            let unlimited: Bool?
            let balance: Double?
            let overageLimitReached: Bool?

            enum CodingKeys: String, CodingKey {
                case hasCredits, unlimited, balance, overageLimitReached
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                hasCredits = try? container.decodeIfPresent(Bool.self, forKey: .hasCredits)
                unlimited = try? container.decodeIfPresent(Bool.self, forKey: .unlimited)
                balance = Self.flexibleDouble(container, key: .balance)
                overageLimitReached = try? container.decodeIfPresent(
                    Bool.self, forKey: .overageLimitReached)
            }

            private static func flexibleDouble(
                _ container: KeyedDecodingContainer<CodingKeys>,
                key: CodingKeys
            ) -> Double? {
                if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
                if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                    return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                return nil
            }
        }
        struct SpendControl: Decodable {
            let limit: Double?
            let used: Double?
            let remainingPercent: Double?
            let resetsAt: Double?

            enum CodingKeys: String, CodingKey {
                case limit, used, remainingPercent, resetsAt
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                limit = Self.flexibleDouble(container, key: .limit)
                used = Self.flexibleDouble(container, key: .used)
                remainingPercent = Self.flexibleDouble(container, key: .remainingPercent)
                resetsAt = Self.flexibleDouble(container, key: .resetsAt)
            }

            private static func flexibleDouble(
                _ container: KeyedDecodingContainer<CodingKeys>,
                key: CodingKeys
            ) -> Double? {
                if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
                if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                    return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                return nil
            }
        }
        struct SpendControlContainer: Decodable {
            let individualLimit: SpendControl?
        }
        struct ResetCredits: Decodable { let availableCount: Int? }
        /// One model-specific bucket from `additional_rate_limits`. Every field
        /// is optional and decoded defensively so a bucket Ammo does not
        /// recognize — or one that arrives in an unexpected shape — degrades to
        /// absence instead of failing the whole usage response.
        struct AdditionalRateLimit: Decodable {
            let limitName: String?
            let meteredFeature: String?
            let rateLimit: RateLimit?

            enum CodingKeys: String, CodingKey {
                case limitName, meteredFeature, rateLimit
            }

            init(from decoder: Decoder) throws {
                guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                    limitName = nil
                    meteredFeature = nil
                    rateLimit = nil
                    return
                }
                limitName = try? container.decodeIfPresent(String.self, forKey: .limitName)
                meteredFeature = try? container.decodeIfPresent(String.self, forKey: .meteredFeature)
                rateLimit = try? container.decodeIfPresent(RateLimit.self, forKey: .rateLimit)
            }
        }
        /// `AdditionalRateLimit` never throws, so this only absorbs the case
        /// where the key holds something other than an array.
        struct AdditionalRateLimits: Decodable {
            let entries: [AdditionalRateLimit]

            init(from decoder: Decoder) throws {
                entries = (try? [AdditionalRateLimit](from: decoder)) ?? []
            }
        }
        let planType: String?
        let rateLimit: RateLimit?
        let additionalRateLimits: AdditionalRateLimits?
        let credits: Credits?
        let individualLimit: SpendControl?
        let spendControl: SpendControlContainer?
        let rateLimitResetCredits: ResetCredits?
    }

    struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double?
        let idToken: String?
    }

    static func windows(from response: Response) -> [LimitWindow] {
        let reported: [Response.Window] =
            [response.rateLimit?.primaryWindow, response.rateLimit?.secondaryWindow]
                .compactMap { $0 }
        let included = reported
            .compactMap { window -> LimitWindow? in
                guard let used = window.usedPercent else { return nil }
                let (kind, label) = classify(windowSeconds: window.limitWindowSeconds)
                return LimitWindow(kind: kind, label: label, usedPercent: used,
                                   resetsAt: window.resetAt.map { Date(timeIntervalSince1970: $0) })
            }
        return included + sparkWindows(from: response)
    }

    // MARK: - Spark buckets

    /// The upstream names for the Spark bucket. They live here, at the Codex
    /// integration boundary, so nothing downstream matches on a vendor string
    /// or a model version that a rename would invalidate.
    private static let sparkLimitNameFragment = "spark"
    private static let sparkMeteredFeature = "codex_bengalfox"

    static func isSparkBucket(_ bucket: Response.AdditionalRateLimit) -> Bool {
        if let feature = bucket.meteredFeature,
           feature.caseInsensitiveCompare(sparkMeteredFeature) == .orderedSame {
            return true
        }
        guard let name = bucket.limitName else { return false }
        return name.range(of: sparkLimitNameFragment, options: .caseInsensitive) != nil
    }

    /// Spark's own short and weekly meters, as ordinary model-scoped windows on
    /// the Codex snapshot. Absent or unrecognized buckets produce nothing: no
    /// synthetic row, no error.
    static func sparkWindows(from response: Response) -> [LimitWindow] {
        guard let buckets = response.additionalRateLimits?.entries, !buckets.isEmpty else {
            return []
        }
        let reported = buckets
            .filter(isSparkBucket)
            .flatMap { bucket -> [Response.Window] in
                [bucket.rateLimit?.primaryWindow, bucket.rateLimit?.secondaryWindow]
                    .compactMap { $0 }
            }
        // Position carries no meaning — a bucket is free to report its weekly
        // window first — so the advertised length, not the payload slot, both
        // labels each meter and fixes the order the bars are drawn in.
        let ordered = reported.sorted { lhs, rhs in
            (lhs.limitWindowSeconds ?? .greatestFiniteMagnitude)
                < (rhs.limitWindowSeconds ?? .greatestFiniteMagnitude)
        }
        var seenIDs = Set<String>()
        return ordered.compactMap { window in
            guard let used = window.usedPercent else { return nil }
            let limitWindow = LimitWindow(
                kind: .modelScoped,
                label: sparkLabel(windowSeconds: window.limitWindowSeconds),
                usedPercent: used,
                resetsAt: window.resetAt.map { Date(timeIntervalSince1970: $0) })
            // `LimitWindow.id` is kind + label, and duplicate ids break the
            // ForEach identity every window list is built on.
            return seenIDs.insert(limitWindow.id).inserted ? limitWindow : nil
        }
    }

    /// Distinct labels per duration class keep `LimitWindow.id` unique while
    /// naming the meter the way the product does.
    static func sparkLabel(windowSeconds: Double?) -> String {
        switch classify(windowSeconds: windowSeconds).0 {
        case .weekly: "Spark weekly"
        case .monthly: "Spark monthly"
        default: "Spark session"
        }
    }

    static func onDemand(from response: Response) -> [OnDemandUsage]? {
        var entries: [OnDemandUsage] = []

        if let credits = response.credits {
            let balance = credits.balance.map { max(0, $0) }
            entries.append(OnDemandUsage(
                id: "codex-usage-credits",
                label: "Usage credits",
                kind: .creditBalance,
                scope: creditScope(planType: response.planType),
                isEnabled: credits.unlimited == true || credits.hasCredits == true,
                isUnlimited: credits.unlimited == true,
                unit: .credits,
                currencyCode: "",
                remaining: balance,
                isExhaustedReported: credits.overageLimitReached
            ))
        }

        if let control = response.spendControl?.individualLimit
            ?? response.individualLimit
            ?? response.rateLimit?.individualLimit {
            let limit = control.limit.map { max(0, $0) }
            let used = control.used.map { max(0, $0) }
            let remaining = limit.map { max(0, $0 - (used ?? 0)) }
            entries.append(OnDemandUsage(
                id: "codex-individual-limit",
                label: "Personal limit",
                kind: .personalAllocation,
                scope: .personal,
                isEnabled: true,
                currencyCode: "USD",
                used: used,
                limit: limit,
                remaining: remaining,
                usedPercent: control.remainingPercent.map { 100 - $0 },
                resetsAt: control.resetsAt.map { Date(timeIntervalSince1970: $0) }
            ))
        }

        return entries.isEmpty ? nil : entries
    }

    static func creditScope(planType: String?) -> OnDemandScope {
        guard let plan = planType?.lowercased() else { return .personal }
        if plan.contains("business") || plan.contains("enterprise") || plan.contains("team") {
            return .organization
        }
        return .personal
    }

    /// Values persisted before source attribution may have come from Ammo's
    /// removed private ChatGPT billing-page capture. Keep the provider's honest
    /// availability marker, but discard unverified balance, conversion, and
    /// expiry fields. A fresh `wham/usage` response carries explicit provenance
    /// and may supply an exact balance without being altered here.
    public static func removingUnverifiedBillingData(
        from snapshot: UsageSnapshot
    ) -> UsageSnapshot {
        guard snapshot.provider == .codex else { return snapshot }
        let sanitized = snapshot.onDemand?.map { usage in
            guard usage.id == "codex-usage-credits",
                  usage.dataSource != .providerUsageResponse,
                  usage.remainingAmount != nil
                    || usage.expiresAt != nil
                    || usage.equivalentAmount != nil
                    || usage.equivalentCurrencyCode != nil
            else { return usage }
            return OnDemandUsage(
                id: usage.id,
                label: usage.label,
                kind: usage.kind,
                scope: usage.scope,
                isEnabled: usage.isEnabled,
                isUnlimited: usage.isUnlimited,
                unit: usage.effectiveUnit,
                dataSource: nil,
                currencyCode: usage.currencyCode,
                isExhaustedReported: usage.isExhaustedReported
            )
        }
        return UsageSnapshot(
            provider: snapshot.provider,
            plan: snapshot.plan,
            windows: snapshot.windows,
            resetCreditsAvailable: snapshot.resetCreditsAvailable,
            onDemand: sanitized,
            fetchedAt: snapshot.fetchedAt
        )
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
