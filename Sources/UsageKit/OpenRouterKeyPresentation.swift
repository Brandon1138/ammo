import Foundation

/// Compact presentation of an OpenRouter key snapshot for surfaces that show
/// every provider side by side and therefore have room for a few lines only.
///
/// OpenRouter reports money and one static entitlement flag, so this type
/// carries exactly those: a credits meter in USD and, when the API reported it,
/// the free-model request cap the key is subject to. The cap is an entitlement,
/// not a counter — free-model requests cost $0.00 and never move the monetary
/// values — so no remaining-request figure is derived from it.
public struct OpenRouterKeyPresentation: Sendable, Equatable {
    /// Budget cadence, recovered from the persisted period rather than guessed
    /// from a countdown.
    public enum Cadence: String, Sendable, Equatable {
        case daily, weekly, monthly

        /// Phrase that keeps a spend figure attached to its period.
        public var periodPhrase: String {
            switch self {
            case .daily: "today"
            case .weekly: "this week"
            case .monthly: "this month"
            }
        }
    }

    /// Dominant value: remaining budget, or the pay-as-you-go label.
    public let headline: String
    /// Supporting line: spend against the budget, or spend to date.
    public let detail: String
    /// Today's reported spend for a key with no budget. `nil` when OpenRouter
    /// did not report a daily aggregate.
    public let dailyDetail: String?
    /// Remaining budget as 0…1. `nil` for a pay-as-you-go key, which has no
    /// capacity to draw a meter against.
    public let remainingFraction: Double?
    public let cadence: Cadence?
    public let resetsAt: Date?
    public let isExhausted: Bool
    /// Static entitlement label, or `nil` when the API omitted `is_free_tier`.
    public let tierBadge: String?

    public var hasBudget: Bool { remainingFraction != nil || resetsAt != nil }

    public init?(snapshot: UsageSnapshot) {
        guard snapshot.provider == .openRouter else { return nil }
        let pools = snapshot.onDemand ?? []
        guard let spending = pools.first(where: { $0.id == Self.spendingPoolID })
            ?? pools.first(where: { $0.effectiveUnit == .currency })
        else { return nil }

        let cadence = Self.cadence(of: spending)
        let daily = pools.first { $0.id == Self.dailyPoolID }

        if !spending.isUnlimited, let remaining = spending.remainingAmount {
            headline = "\(Self.money(remaining, code: spending.currencyCode)) left"
            if let used = spending.used, let limit = spending.limit {
                let period = cadence.map { " \($0.periodPhrase)" } ?? ""
                detail = "\(Self.money(used, code: spending.currencyCode)) of "
                    + "\(Self.money(limit, code: spending.currencyCode)) used\(period)"
            } else if let limit = spending.limit {
                detail = "\(Self.money(limit, code: spending.currencyCode)) budget"
            } else {
                detail = "Provider-reported balance"
            }
            dailyDetail = nil
        } else {
            headline = "Pay-as-you-go"
            if let used = spending.used {
                detail = "\(Self.money(used, code: spending.currencyCode)) spent to date"
            } else {
                detail = "No spend reported"
            }
            dailyDetail = daily?.used.map {
                "\(Self.money($0, code: daily?.currencyCode ?? "USD")) today"
            }
        }

        remainingFraction = spending.isUnlimited ? nil : spending.remainingFraction
        self.cadence = cadence
        resetsAt = spending.resetsAt
        isExhausted = spending.isExhausted
        tierBadge = Self.tierBadge(isFreeTier: snapshot.isFreeTier)
    }

    static let spendingPoolID = "openrouter-key-spending"
    static let dailyPoolID = "openrouter-key-daily-spend"

    /// Free-tier keys are capped at 50 free-model requests per day; paid keys at
    /// 1000. Both numbers are OpenRouter policy attached to the reported flag,
    /// which is why an unreported flag produces no badge at all.
    static func tierBadge(isFreeTier: Bool?) -> String? {
        switch isFreeTier {
        case true: "Free tier · 50 free req/day cap"
        case false: "1000 free req/day cap"
        case nil: nil
        }
    }

    private static func cadence(of usage: OnDemandUsage) -> Cadence? {
        guard let start = usage.periodStart, let end = usage.resetsAt, end > start else {
            return nil
        }
        let days = end.timeIntervalSince(start) / 86_400
        switch days {
        case 0.5..<2: return .daily
        case 6..<8: return .weekly
        case 27..<32: return .monthly
        default: return nil
        }
    }

    private static func money(_ amount: Double, code: String) -> String {
        amount.formatted(.currency(code: code).precision(.fractionLength(2)))
    }
}
