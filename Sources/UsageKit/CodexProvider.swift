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
                             resetCreditsAvailable: response.rateLimitResetCredits?.availableCount,
                             onDemand: Self.onDemand(from: response))
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
        let planType: String?
        let rateLimit: RateLimit?
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
        [response.rateLimit?.primaryWindow, response.rateLimit?.secondaryWindow]
            .compactMap { $0 }
            .compactMap { window in
                guard let used = window.usedPercent else { return nil }
                let (kind, label) = classify(windowSeconds: window.limitWindowSeconds)
                return LimitWindow(kind: kind, label: label, usedPercent: used,
                                   resetsAt: window.resetAt.map { Date(timeIntervalSince1970: $0) })
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

    // MARK: - Separately authenticated workspace billing

    /// Exact response from the ChatGPT Admin billing page's first-party endpoint,
    /// captured live 2026-07-21. This contract intentionally stays separate from
    /// `wham/usage`: the Codex OAuth token can truthfully say credits exist while
    /// omitting their organization balance.
    struct BillingBalanceResponse: Decodable {
        struct ExpiringBalance: Decodable {
            let amountGranted: Double?
            let amountRemaining: Double?
            let expiryDate: String?
            let grantType: String?

            enum CodingKeys: String, CodingKey {
                case amountGranted, amountRemaining, expiryDate, grantType
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                amountGranted = Self.flexibleDouble(container, key: .amountGranted)
                amountRemaining = Self.flexibleDouble(container, key: .amountRemaining)
                expiryDate = try? container.decodeIfPresent(String.self, forKey: .expiryDate)
                grantType = try? container.decodeIfPresent(String.self, forKey: .grantType)
            }

            private static func flexibleDouble(
                _ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys
            ) -> Double? {
                if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                    return value
                }
                if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                    return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                return nil
            }
        }

        let balance: Double?
        let expiringBalanceDetails: [ExpiringBalance]?

        enum CodingKeys: String, CodingKey { case balance, expiringBalanceDetails }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let value = try? container.decodeIfPresent(Double.self, forKey: .balance) {
                balance = value
            } else if let value = try? container.decodeIfPresent(String.self, forKey: .balance) {
                balance = Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                balance = nil
            }
            expiringBalanceDetails = try? container.decodeIfPresent(
                [ExpiringBalance].self, forKey: .expiringBalanceDetails)
        }
    }

    /// Parses a sanitized `remaining_balance` response captured inside Ammo's
    /// persistent WKWebView. `pageText` is optional and used only to retain the
    /// billing page's local-currency equivalent (for example RON 3,622.81).
    public static func billingOnDemandUsage(
        from data: Data,
        pageText: String? = nil
    ) throws -> OnDemandUsage {
        let response: BillingBalanceResponse
        do {
            response = try decoder.decode(BillingBalanceResponse.self, from: data)
        } catch {
            throw UsageError.malformedResponse("codex billing balance: \(error)")
        }
        guard let balance = response.balance else {
            throw UsageError.malformedResponse("codex billing balance: missing balance")
        }
        let expiration = response.expiringBalanceDetails?
            .filter { ($0.amountRemaining ?? 0) > 0 }
            .compactMap { ISO8601.parse($0.expiryDate) }
            .min()
        let equivalent = pageText.flatMap(localCurrencyEquivalent)
        return OnDemandUsage(
            id: "codex-usage-credits",
            label: "Usage credits",
            kind: .creditBalance,
            scope: .organization,
            isEnabled: true,
            unit: .credits,
            currencyCode: "",
            remaining: max(0, balance),
            expiresAt: expiration,
            equivalentAmount: equivalent?.amount,
            equivalentCurrencyCode: equivalent?.currencyCode
        )
    }

    static func localCurrencyEquivalent(_ pageText: String) -> (currencyCode: String, amount: Double)? {
        let pattern = #"[0-9][0-9\s.,]*\s*/\s*([A-Z]{3})\s*([0-9][0-9\s.,]*)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: pageText,
                range: NSRange(pageText.startIndex..., in: pageText)),
              let currencyRange = Range(match.range(at: 1), in: pageText),
              let amountRange = Range(match.range(at: 2), in: pageText)
        else { return nil }
        let currency = String(pageText[currencyRange])
        let rawAmount = String(pageText[amountRange])
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let amount = Double(rawAmount) else { return nil }
        return (currency, amount)
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
