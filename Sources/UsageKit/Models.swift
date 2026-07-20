import Foundation

/// A service whose usage limits Ammo can display.
public enum ProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case claude
    case codex
    // Known issue: planned, not yet implemented. See SPEC.md "Deferred providers".
    case cursor
    case antigravity

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .antigravity: "Antigravity"
        }
    }
}

public enum WindowKind: String, Codable, Sendable {
    case session      // short rolling window (Claude 5h)
    case weekly
    case monthly
    case modelScoped  // per-model bucket (e.g. Claude "Fable"/"Opus")
    case unknown
}

/// One rate-limit window, normalized across providers.
public struct LimitWindow: Codable, Sendable, Identifiable, Equatable {
    public let kind: WindowKind
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public var id: String { "\(kind.rawValue):\(label)" }
    public var remainingPercent: Double { min(100, max(0, 100 - usedPercent)) }

    public init(kind: WindowKind, label: String, usedPercent: Double, resetsAt: Date?) {
        self.kind = kind
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// The result of one usage fetch for one account.
public struct UsageSnapshot: Codable, Sendable, Equatable {
    public let provider: ProviderID
    public let plan: String?
    public let windows: [LimitWindow]
    /// Codex: number of "rate limit reset" credits available (nil where not applicable).
    public let resetCreditsAvailable: Int?
    public let fetchedAt: Date

    public init(provider: ProviderID, plan: String?, windows: [LimitWindow],
                resetCreditsAvailable: Int? = nil, fetchedAt: Date = Date()) {
        self.provider = provider
        self.plan = plan
        self.windows = windows
        self.resetCreditsAvailable = resetCreditsAvailable
        self.fetchedAt = fetchedAt
    }
}

/// OAuth credential material for one account. Stored only in the device Keychain.
public struct OAuthTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?
    /// Provider-specific account id. Codex sends it as `ChatGPT-Account-Id`;
    /// Cursor uses it to construct its first-party web-session cookie.
    public var accountID: String?

    public init(accessToken: String, refreshToken: String? = nil,
                expiresAt: Date? = nil, accountID: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountID = accountID
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 60
    }
}

public enum UsageError: Error, CustomStringConvertible {
    case http(status: Int, body: String)
    case malformedResponse(String)
    case notAuthenticated(String)

    public var description: String {
        switch self {
        case .http(let status, let body): return "HTTP \(status): \(body.prefix(300))"
        case .malformedResponse(let detail): return "Malformed response: \(detail)"
        case .notAuthenticated(let detail): return "Not authenticated: \(detail)"
        }
    }
}
