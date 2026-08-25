import Foundation

/// Cursor usage adapter.
///
/// Cursor does not publish an individual-plan usage API. This adapter mirrors
/// Cursor's first-party PKCE login and reads the same private dashboard summary
/// used by Cursor's own web UI. Keep the contract date-stamped and tolerant.
public struct CursorProvider: UsageProvider {
    public let id = ProviderID.cursor

    public static let usageURL = URL(string: "https://cursor.com/api/usage-summary")!
    public static let loginURL = URL(string: "https://cursor.com/loginDeepControl")!
    public static let pollURL = URL(string: "https://api2.cursor.sh/auth/poll")!
    public static let tokenURL = URL(string: "https://api2.cursor.sh/oauth/token")!
    /// Public client id embedded in Cursor 3.7.27.
    public static let clientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"

    /// Cursor's shared first-party pool (Grok, Composer, and whichever other
    /// Cursor-priced models the plan currently includes). It is one quota; the
    /// individual models inside it are not separately metered.
    public static let cursorModelsLabel = "Cursor Models"
    /// Cursor's third-party, API-priced pool (Claude, GPT, Gemini, …).
    public static let otherModelsLabel = "Other Models"
    /// Labels shipped before MIK-152. Persisted snapshots still carry them, and
    /// window identity is `kind:label`, so history continuity depends on
    /// rewriting them on the way in rather than only relabelling new fetches.
    static let legacyWindowLabels = [
        "Composer": cursorModelsLabel,
        "API": otherModelsLabel,
    ]

    /// Rewrites pre-MIK-152 Cursor window labels. Windows Cursor never emitted
    /// under those names are returned untouched.
    public static func migratingLegacyWindowLabels(_ windows: [LimitWindow]) -> [LimitWindow] {
        windows.map { window in
            guard window.kind == .monthly,
                  let renamed = legacyWindowLabels[window.label] else { return window }
            return LimitWindow(kind: window.kind,
                               label: renamed,
                               usedPercent: window.usedPercent,
                               resetsAt: window.resetsAt)
        }
    }

    let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func fetchUsage(tokens: OAuthTokens) async throws -> UsageSnapshot {
        let cookie = try Self.cookieHeader(tokens: tokens)
        let data = try await transport.get(Self.usageURL, headers: [
            "Accept": "application/json",
            "Cookie": cookie,
        ])
        return try Self.snapshot(from: data)
    }

    /// Parses one successful usage-summary body into the normalized snapshot
    /// shared by the app and widget. Keeping this seam public lets the shared
    /// cache repair a windowless legacy snapshot from its retained response
    /// without teaching the widget about Cursor's wire format.
    public static func snapshot(from data: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        let response: Response
        do {
            response = try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw UsageError.malformedResponse(
                "cursor usage: \(error); \(Self.shapeDiagnostics(from: data))")
        }
        let windows = Self.windows(from: response)
        let onDemand = Self.onDemand(from: response)
        guard !windows.isEmpty || onDemand != nil else {
            throw UsageError.malformedResponse(
                "cursor usage: response contained no included or on-demand usage; \(Self.shapeDiagnostics(from: data))")
        }
        return UsageSnapshot(provider: .cursor,
                             plan: response.membershipType,
                             windows: windows,
                             onDemand: onDemand,
                             fetchedAt: fetchedAt)
    }

    public func refresh(tokens: OAuthTokens) async throws -> OAuthTokens {
        guard let refreshToken = tokens.refreshToken else {
            throw UsageError.notAuthenticated("cursor: no refresh token")
        }
        let body = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": Self.clientID,
            "refresh_token": refreshToken,
        ])
        let data = try await transport.post(Self.tokenURL,
                                            headers: ["Content-Type": "application/json"],
                                            body: body)
        let response: RefreshResponse
        do {
            response = try Self.decoder.decode(RefreshResponse.self, from: data)
        } catch {
            throw UsageError.malformedResponse("cursor token: \(error)")
        }
        guard response.shouldLogout != true else {
            throw UsageError.notAuthenticated("cursor: the server requested a new sign-in")
        }
        // Current Cursor builds use the returned access token as the next
        // refresh credential when a distinct refresh_token is omitted.
        return OAuthTokens(accessToken: response.accessToken,
                           refreshToken: response.refreshToken ?? response.accessToken,
                           expiresAt: Self.expiration(fromJWT: response.accessToken),
                           accountID: Self.userID(fromJWT: response.accessToken))
    }

    /// Cursor's login page has no callback to Ammo. The UUID binds the browser
    /// approval to the polling request that carries the PKCE verifier.
    public static func authorizationRequestURL(pkce: PKCE, uuid: UUID) -> URL {
        var components = URLComponents(url: loginURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "challenge", value: pkce.challenge),
            URLQueryItem(name: "uuid", value: uuid.uuidString.lowercased()),
            URLQueryItem(name: "mode", value: "login"),
            URLQueryItem(name: "supportsSelectedTeamLogin", value: "true"),
        ]
        return components.url!
    }

    /// One non-blocking poll. A 404 means the browser approval is still pending.
    public func pollForTokens(uuid: UUID, verifier: String) async throws -> OAuthTokens? {
        var components = URLComponents(url: Self.pollURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "uuid", value: uuid.uuidString.lowercased()),
            URLQueryItem(name: "verifier", value: verifier),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, status) = try await transport.request(request)
        if status == 404 { return nil }
        guard (200..<300).contains(status) else {
            throw UsageError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        let response: PollResponse
        do {
            response = try Self.decoder.decode(PollResponse.self, from: data)
        } catch {
            throw UsageError.malformedResponse("cursor login poll: \(error)")
        }
        return OAuthTokens(accessToken: response.accessToken,
                           refreshToken: response.refreshToken,
                           expiresAt: Self.expiration(fromJWT: response.accessToken),
                           accountID: Self.userID(fromJWT: response.accessToken))
    }

    // MARK: - Response mapping

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    struct Response: Decodable {
        struct MonetaryUsage: Decodable {
            let enabled: Bool?
            let isUnlimited: Bool?
            /// Cursor reports all monetary values in cents.
            let used: Int?
            let limit: Int?
            let remaining: Int?
        }

        struct IndividualUsage: Decodable {
            struct Plan: Decodable {
                struct Breakdown: Decodable {
                    let included: Int?
                    let bonus: Int?
                    let total: Int?
                }

                let enabled: Bool?
                let used: Int?
                let limit: Int?
                let remaining: Int?
                let breakdown: Breakdown?
                let autoPercentUsed: Double?
                let composerPercentUsed: Double?
                let firstPartyPercentUsed: Double?
                let apiPercentUsed: Double?
                let totalPercentUsed: Double?

                /// Cursor's shared first-party pool. The field has been renamed
                /// upstream twice already, so every observed spelling is tried
                /// and an unknown shape stays nil (unavailable) rather than 0.
                var cursorModelsUsedPercent: Double? {
                    firstPartyPercentUsed ?? composerPercentUsed ?? autoPercentUsed
                }
            }
            let plan: Plan?
            let onDemand: MonetaryUsage?
            /// Team and enterprise members may receive a personal cap here
            /// even when the ordinary `plan` block is absent.
            let overall: MonetaryUsage?
        }

        struct TeamUsage: Decodable {
            let onDemand: MonetaryUsage?
            /// Shared team/enterprise pool across members.
            let pooled: MonetaryUsage?
        }

        let billingCycleStart: String?
        let billingCycleEnd: String?
        let membershipType: String?
        let limitType: String?
        let isUnlimited: Bool?
        let autoModelSelectedDisplayMessage: String?
        let namedModelSelectedDisplayMessage: String?
        let individualUsage: IndividualUsage?
        let teamUsage: TeamUsage?
    }

    struct PollResponse: Decodable {
        let accessToken: String
        let refreshToken: String
    }

    struct RefreshResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let shouldLogout: Bool?
    }

    static func windows(from response: Response) -> [LimitWindow] {
        let reset = ISO8601.parse(response.billingCycleEnd)
        let plan = response.individualUsage?.plan
        // Numeric plan fields always win. Display-message percents fill only
        // the windows those fields did not supply. `totalPercentUsed` is a
        // last-resort single Cursor Models window, never a third pool and
        // never a replacement for a specific field or a parsed message.
        var cursorModels = plan?.cursorModelsUsedPercent
        var otherModels = plan?.apiPercentUsed
        if cursorModels == nil {
            cursorModels = percent(fromDisplayMessage: response.autoModelSelectedDisplayMessage)
        }
        if otherModels == nil {
            otherModels = percent(fromDisplayMessage: response.namedModelSelectedDisplayMessage)
        }
        if cursorModels == nil, otherModels == nil {
            cursorModels = plan?.totalPercentUsed
        }

        var windows: [LimitWindow] = []
        if let cursorModels {
            windows.append(LimitWindow(kind: .monthly,
                                       label: cursorModelsLabel,
                                       usedPercent: clampPercent(cursorModels),
                                       resetsAt: reset))
        }
        if let otherModels {
            windows.append(LimitWindow(kind: .monthly,
                                       label: otherModelsLabel,
                                       usedPercent: clampPercent(otherModels),
                                       resetsAt: reset))
        }
        return windows
    }

    /// Team and token-based seats often ship included usage only as copy such
    /// as "You've used 42% of your included total usage". A message must yield
    /// exactly one `%` figure; anything else is ignored rather than guessed.
    static func percent(fromDisplayMessage message: String?) -> Double? {
        guard let message else { return nil }
        let matches = message.matches(of: /(\d+(?:\.\d+)?)\s*%/)
        guard matches.count == 1, let value = Double(matches[0].output.1) else { return nil }
        return clampPercent(value)
    }

    static func onDemand(from response: Response) -> [OnDemandUsage]? {
        let periodStart = ISO8601.parse(response.billingCycleStart)
        let resetsAt = ISO8601.parse(response.billingCycleEnd)
        var entries: [OnDemandUsage] = []

        func append(
            _ value: Response.MonetaryUsage?,
            id: String,
            label: String,
            kind: OnDemandKind,
            scope: OnDemandScope
        ) {
            guard let value else { return }
            let used = value.used.map(Self.majorCurrencyUnits)
            let limit = value.limit.map(Self.majorCurrencyUnits)
            let remaining = value.remaining.map(Self.majorCurrencyUnits)
            entries.append(OnDemandUsage(
                id: id,
                label: label,
                kind: kind,
                scope: scope,
                isEnabled: value.enabled,
                isUnlimited: value.isUnlimited == true,
                currencyCode: "USD",
                used: used,
                limit: limit,
                remaining: remaining,
                periodStart: periodStart,
                resetsAt: resetsAt
            ))
        }

        append(response.individualUsage?.onDemand,
               id: "cursor-personal-on-demand",
               label: "Personal on-demand",
               kind: .spendingLimit,
               scope: .personal)
        append(response.individualUsage?.overall,
               id: "cursor-personal-allocation",
               label: "Personal allocation",
               kind: .personalAllocation,
               scope: .personal)
        append(response.teamUsage?.onDemand,
               id: "cursor-team-on-demand",
               label: "Team on-demand",
               kind: .teamBudget,
               scope: .team)
        append(response.teamUsage?.pooled,
               id: "cursor-shared-pool",
               label: "Shared pool",
               kind: .pooledBudget,
               scope: .organization)

        return entries.isEmpty ? nil : entries
    }

    static func cookieHeader(tokens: OAuthTokens) throws -> String {
        guard let userID = tokens.accountID ?? userID(fromJWT: tokens.accessToken) else {
            throw UsageError.notAuthenticated("cursor: access token has no user id")
        }
        return "WorkosCursorSessionToken=\(userID)%3A%3A\(tokens.accessToken)"
    }

    static func userID(fromJWT jwt: String) -> String? {
        guard let subject = claims(fromJWT: jwt)?["sub"] as? String,
              let userID = subject.split(separator: "|", omittingEmptySubsequences: true)
                .last.map(String.init),
              !userID.isEmpty
        else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard userID.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return userID
    }

    static func expiration(fromJWT jwt: String) -> Date? {
        guard let expiration = claims(fromJWT: jwt)?["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: expiration.doubleValue)
    }

    private static func claims(fromJWT jwt: String) -> [String: Any]? {
        let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let payload = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
    }

    private static func clampPercent(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private static func majorCurrencyUnits(_ cents: Int) -> Double {
        max(0, Double(cents)) / 100
    }

    /// Shape crumbs for a usage-summary body that decoded as empty or invalid.
    /// Cookies and tokens are stripped; the snippet is capped so it can sit
    /// next to the recorded `malformedResponse` without becoming a dump.
    static func shapeDiagnostics(from data: Data) -> String {
        "\(planKeyPaths(in: data)); body: \(sanitizedBodySnippet(data))"
    }

    static func planKeyPaths(in data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "individualUsage.plan: (not JSON)"
        }
        let individual = json["individualUsage"] ?? json["individual_usage"]
        guard let individualDict = individual as? [String: Any] else {
            return "individualUsage.plan: absent"
        }
        guard let plan = individualDict["plan"] else {
            return "individualUsage.plan: absent"
        }
        guard let planDict = plan as? [String: Any] else {
            return "individualUsage.plan: (not object)"
        }
        if planDict.isEmpty {
            return "individualUsage.plan keys: (empty)"
        }
        let paths = flattenKeys(planDict, prefix: "individualUsage.plan").sorted()
        return "individualUsage.plan keys: \(paths.joined(separator: ", "))"
    }

    static func sanitizedBodySnippet(_ data: Data, maxBytes: Int = 2048) -> String {
        let text: String
        if let json = try? JSONSerialization.jsonObject(with: data) {
            let sanitized = sanitizeJSON(json)
            if JSONSerialization.isValidJSONObject(sanitized),
               let encoded = try? JSONSerialization.data(
                    withJSONObject: sanitized, options: [.sortedKeys]),
               let string = String(data: encoded, encoding: .utf8) {
                text = string
            } else {
                text = redactSecretText(String(decoding: data, as: UTF8.self))
            }
        } else {
            text = redactSecretText(String(decoding: data, as: UTF8.self))
        }
        return truncatingUTF8(text, maxBytes: maxBytes)
    }

    private static let sensitiveKeyFragments = [
        "cookie", "token", "authorization", "password", "secret", "session", "bearer",
    ]

    private static func sanitizeJSON(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            out.reserveCapacity(dict.count)
            for (key, nested) in dict {
                if isSensitiveKey(key) {
                    out[key] = "<redacted>"
                } else {
                    out[key] = sanitizeJSON(nested)
                }
            }
            return out
        }
        if let array = value as? [Any] {
            return array.map(sanitizeJSON)
        }
        if let string = value as? String, looksLikeSecret(string) {
            return "<redacted>"
        }
        return value
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return sensitiveKeyFragments.contains { lowered.contains($0) }
    }

    private static func looksLikeSecret(_ string: String) -> Bool {
        if string.localizedCaseInsensitiveContains("WorkosCursorSessionToken") { return true }
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { $0.count >= 8 }
    }

    private static func redactSecretText(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"WorkosCursorSessionToken=[^\s\"\\,]+"#,
            with: "WorkosCursorSessionToken=<redacted>",
            options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#,
            with: "<redacted>",
            options: .regularExpression)
        return result
    }

    private static func flattenKeys(_ dict: [String: Any], prefix: String) -> [String] {
        dict.flatMap { key, value -> [String] in
            let path = "\(prefix).\(key)"
            if let nested = value as? [String: Any], !nested.isEmpty {
                return flattenKeys(nested, prefix: path)
            }
            return [path]
        }
    }

    private static func truncatingUTF8(_ string: String, maxBytes: Int) -> String {
        var count = 0
        var end = string.startIndex
        for index in string.indices {
            let charBytes = string[index].utf8.count
            if count + charBytes > maxBytes { break }
            count += charBytes
            end = string.index(after: index)
        }
        if end == string.endIndex { return string }
        return String(string[..<end]) + "…"
    }
}
