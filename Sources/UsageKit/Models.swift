import Foundation

/// A service whose usage limits Ammo can display.
public enum ProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case claude
    case codex
    case cursor
    case openRouter = "openrouter"
    // Known issue: planned, not yet implemented. See SPEC.md "Deferred providers".
    case antigravity

    /// Providers that have complete onboarding and refresh paths in this build.
    /// `allCases` also contains persisted/deferred identities for decode safety.
    public static let supported: [ProviderID] = [.claude, .codex, .cursor, .openRouter]

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .openRouter: "OpenRouter"
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

/// How a provider funds usage after (or instead of) an included allowance.
/// These values deliberately stay separate from `LimitWindow`: money and
/// provider credits cannot be combined honestly with a time-window percentage.
public enum OnDemandKind: String, Codable, Sendable, Equatable {
    case creditBalance
    case spendingLimit
    case personalAllocation
    case teamBudget
    case pooledBudget
}

public enum OnDemandScope: String, Codable, Sendable, Equatable {
    case personal
    case team
    case organization
}

/// The native unit used by an on-demand pool. Provider credits are deliberately
/// distinct from money: a credit balance must never be formatted as USD merely
/// because another provider reports monetary spend controls.
public enum OnDemandUnit: String, Codable, Sendable, Equatable {
    case currency
    case credits
}

/// Provenance for values that are safe to persist and present. Optional so
/// snapshots written before provenance tracking decode as unverified.
public enum OnDemandDataSource: String, Codable, Sendable, Equatable {
    case providerUsageResponse
}

/// One provider-reported pool of paid, on-demand capacity.
/// Monetary values are normalized to major currency units (for example,
/// dollars rather than cents) before entering this model.
public struct OnDemandUsage: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let label: String
    public let kind: OnDemandKind
    public let scope: OnDemandScope
    public let isEnabled: Bool?
    public let isUnlimited: Bool
    /// Optional only so snapshots persisted by builds before unit-aware balances
    /// continue to decode. New values always set this through the initializer.
    public let unit: OnDemandUnit?
    /// Nil means a persisted value predates source attribution and must not be
    /// trusted when its origin affects safety or correctness.
    public let dataSource: OnDemandDataSource?
    public let currencyCode: String
    public let used: Double?
    public let limit: Double?
    /// The provider's explicit remaining value when one exists. If omitted,
    /// `remainingAmount` derives it from `limit - used`.
    public let remaining: Double?
    /// Provider-reported utilization when it cannot be reconstructed exactly
    /// from monetary values (0...100).
    public let usedPercent: Double?
    public let periodStart: Date?
    public let resetsAt: Date?
    /// Credit grants expire; that is not the same event as a recurring spend-cap reset.
    public let expiresAt: Date?
    /// Optional provider-page conversion for non-monetary balances.
    public let equivalentAmount: Double?
    public let equivalentCurrencyCode: String?
    /// Some providers explicitly report exhaustion even when they omit an amount.
    public let isExhaustedReported: Bool?

    public init(
        id: String,
        label: String,
        kind: OnDemandKind,
        scope: OnDemandScope,
        isEnabled: Bool? = nil,
        isUnlimited: Bool = false,
        unit: OnDemandUnit = .currency,
        dataSource: OnDemandDataSource? = .providerUsageResponse,
        currencyCode: String = "USD",
        used: Double? = nil,
        limit: Double? = nil,
        remaining: Double? = nil,
        usedPercent: Double? = nil,
        periodStart: Date? = nil,
        resetsAt: Date? = nil,
        expiresAt: Date? = nil,
        equivalentAmount: Double? = nil,
        equivalentCurrencyCode: String? = nil,
        isExhaustedReported: Bool? = nil
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.scope = scope
        self.isEnabled = isEnabled
        self.isUnlimited = isUnlimited
        self.unit = unit
        self.dataSource = dataSource
        self.currencyCode = currencyCode.uppercased()
        self.used = used
        self.limit = limit
        self.remaining = remaining
        self.usedPercent = usedPercent.map { min(100, max(0, $0)) }
        self.periodStart = periodStart
        self.resetsAt = resetsAt
        self.expiresAt = expiresAt
        self.equivalentAmount = equivalentAmount.map { max(0, $0) }
        self.equivalentCurrencyCode = equivalentCurrencyCode?.uppercased()
        self.isExhaustedReported = isExhaustedReported
    }

    public var remainingAmount: Double? {
        if let remaining { return max(0, remaining) }
        guard let limit else { return nil }
        return max(0, limit - (used ?? 0))
    }

    public var remainingFraction: Double? {
        if let limit, limit > 0, let remainingAmount {
            return min(1, max(0, remainingAmount / limit))
        }
        return usedPercent.map { min(1, max(0, (100 - $0) / 100)) }
    }

    public var isExhausted: Bool {
        guard isEnabled != false, !isUnlimited else { return false }
        if isExhaustedReported == true { return true }
        return remainingAmount.map { $0 <= 0.000_001 } ?? false
    }

    public var effectiveUnit: OnDemandUnit { unit ?? .currency }
}

/// The result of one usage fetch for one account.
public struct UsageSnapshot: Codable, Sendable, Equatable {
    public let provider: ProviderID
    public let plan: String?
    public let windows: [LimitWindow]
    /// Codex: number of "rate limit reset" credits available (nil where not applicable).
    public let resetCreditsAvailable: Int?
    /// Paid continuation capacity reported by the provider. `nil` means the
    /// contract supplied no on-demand data; an entry with `isEnabled == false`
    /// means the provider explicitly reported that pool as disabled.
    public let onDemand: [OnDemandUsage]?
    /// Provider-reported free-tier entitlement for the credential behind this
    /// snapshot (OpenRouter's `is_free_tier`). `nil` means the provider did not
    /// report a tier, in which case no tier may be claimed in the UI.
    public let isFreeTier: Bool?
    public let fetchedAt: Date

    public init(provider: ProviderID, plan: String?, windows: [LimitWindow],
                resetCreditsAvailable: Int? = nil,
                onDemand: [OnDemandUsage]? = nil,
                isFreeTier: Bool? = nil,
                fetchedAt: Date = Date()) {
        self.provider = provider
        self.plan = plan
        self.windows = windows
        self.resetCreditsAvailable = resetCreditsAvailable
        self.onDemand = onDemand
        self.isFreeTier = isFreeTier
        self.fetchedAt = fetchedAt
    }

    /// Decoding is where persisted snapshots re-enter the app, so provider
    /// label migrations belong here: a cached or historical snapshot must
    /// present the same window identity (`kind:label`) as a fresh fetch, or the
    /// history graphs read the rename as the window disappearing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(ProviderID.self, forKey: .provider)
        plan = try container.decodeIfPresent(String.self, forKey: .plan)
        let decodedWindows = try container.decode([LimitWindow].self, forKey: .windows)
        windows = provider == .cursor
            ? CursorProvider.migratingLegacyWindowLabels(decodedWindows)
            : decodedWindows
        resetCreditsAvailable = try container.decodeIfPresent(Int.self,
                                                             forKey: .resetCreditsAvailable)
        onDemand = try container.decodeIfPresent([OnDemandUsage].self, forKey: .onDemand)
        isFreeTier = try container.decodeIfPresent(Bool.self, forKey: .isFreeTier)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
    }
}

public extension UsageSnapshot {
    /// First exact monetary balance safe for compact shared surfaces such as
    /// widgets. Legacy entries without source attribution, provider credits,
    /// disabled pools, and amount-less values fail closed.
    var verifiedMonetaryOnDemandBalance: OnDemandUsage? {
        onDemand?.first {
            $0.dataSource == .providerUsageResponse
                && $0.effectiveUnit == .currency
                && $0.isEnabled != false
                && $0.remainingAmount != nil
                && !$0.currencyCode.isEmpty
        }
    }

    /// Stable, provider-aware plan copy for UI badges. Unknown future values get
    /// a readable word-wise fallback instead of Swift's underscore-preserving
    /// `capitalized` output.
    var displayPlan: String? {
        guard let plan, !plan.isEmpty else { return nil }
        switch (provider, plan.lowercased()) {
        case (.codex, "self_serve_business_usage_based"):
            return "Business"
        // ChatGPT's 5x tier reports "prolite", which is not a name anyone
        // subscribes under. Both paid individual tiers read as Pro.
        case (.codex, "prolite"), (.codex, "pro"):
            return "Pro"
        default:
            return plan
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
                .joined(separator: " ")
        }
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
