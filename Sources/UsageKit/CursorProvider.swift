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
        let response: Response
        do {
            response = try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw UsageError.malformedResponse("cursor usage: \(error)")
        }
        let windows = Self.windows(from: response)
        guard windows.count == 2 else {
            throw UsageError.malformedResponse(
                "cursor usage: expected both Composer and included API percentages")
        }
        return UsageSnapshot(provider: .cursor,
                             plan: response.membershipType,
                             windows: windows)
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
        struct IndividualUsage: Decodable {
            struct Plan: Decodable {
                let autoPercentUsed: Double?
                let composerPercentUsed: Double?
                let firstPartyPercentUsed: Double?
                let apiPercentUsed: Double?

                var composerUsedPercent: Double? {
                    firstPartyPercentUsed ?? composerPercentUsed ?? autoPercentUsed
                }
            }
            let plan: Plan?
        }

        let billingCycleEnd: String?
        let membershipType: String?
        let individualUsage: IndividualUsage?
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
        var windows: [LimitWindow] = []
        if let composer = plan?.composerUsedPercent {
            windows.append(LimitWindow(kind: .monthly,
                                       label: "Composer",
                                       usedPercent: clampPercent(composer),
                                       resetsAt: reset))
        }
        if let api = plan?.apiPercentUsed {
            windows.append(LimitWindow(kind: .monthly,
                                       label: "API",
                                       usedPercent: clampPercent(api),
                                       resetsAt: reset))
        }
        return windows
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
}
