import Foundation

/// Provider-neutral Lock Screen presentation for an account whose provider
/// reported paid, on-demand pools rather than percentage windows.
///
/// Percentage windows always win the gauge — `LockScreenUsagePresentation` is
/// tried first. This type exists for the states where a provider reports spend
/// and nothing else, which on the shipping providers means:
///
/// * OpenRouter, whose key snapshot is money by construction, and
/// * Cursor, whose `usage-summary` omits the `individualUsage.plan` block for
///   team and enterprise members and for usage-based plans, leaving only the
///   on-demand pools.
///
/// Before this type existed the Lock Screen had an OpenRouter-only gauge and a
/// static `ProviderLogo` + dollar-glyph stack for everyone else. That stack was
/// bound to no snapshot value, so a Cursor account in this state rendered the
/// same glyph forever no matter how many fresh timelines arrived.
public struct MeteredLockScreenPresentation: Sendable, Equatable {
    /// The pool the gauge is drawn from.
    public let pool: OnDemandUsage
    /// Remaining capacity as 0…1, or `nil` for a pool with no capacity to draw
    /// a meter against (unlimited, or amount-only spend reporting).
    public let remainingFraction: Double?
    /// Currency or credit copy sized for the gauge center. `nil` means the
    /// provider reported no amount worth printing and the gauge should fall
    /// back to `centerFallbackSymbol`.
    public let centerText: String?
    /// SF Symbol for the center when there is no amount to print.
    public let centerFallbackSymbol: String
    /// Spoken description of the meter, without the account or failure context
    /// the widget adds around it.
    public let accessibilityDescription: String
    public let fetchedAt: Date

    public init?(snapshot: UsageSnapshot) {
        // OpenRouter already ships a purpose-built key presentation whose
        // pay-as-you-go center reads today's spend from a second pool. Delegate
        // rather than re-derive it, so that gauge is untouched by this path.
        if snapshot.provider == .openRouter {
            guard let key = OpenRouterKeyPresentation(snapshot: snapshot),
                  let pool = Self.eligiblePools(in: snapshot).first
            else { return nil }
            self.pool = pool
            remainingFraction = key.remainingFraction
            centerText = key.lockScreenCenterText
            centerFallbackSymbol = Self.fallbackSymbol(for: pool)
            accessibilityDescription = Self.openRouterAccessibilityDescription(
                provider: snapshot.provider, key: key)
            fetchedAt = snapshot.fetchedAt
            return
        }

        guard let pool = Self.preferredPool(in: snapshot) else { return nil }
        let fraction = pool.isUnlimited ? nil : pool.remainingFraction

        self.pool = pool
        remainingFraction = fraction
        centerText = Self.centerText(for: pool, remainingFraction: fraction)
        centerFallbackSymbol = Self.fallbackSymbol(for: pool)
        accessibilityDescription = Self.accessibilityDescription(
            for: pool, remainingFraction: fraction)
        fetchedAt = snapshot.fetchedAt
    }

    // MARK: - Pool selection

    /// Pools the provider reported as usable and that carry a number the gauge
    /// can print. Payload order is preserved; providers list their own pools in
    /// the order they consider primary.
    static func eligiblePools(in snapshot: UsageSnapshot) -> [OnDemandUsage] {
        (snapshot.onDemand ?? []).filter { pool in
            pool.isEnabled != false && (pool.used != nil || pool.remainingAmount != nil)
        }
    }

    /// A pool that can fill the arc beats one that can only print a number, and
    /// the person's own meter beats a shared team or organization budget. Ties
    /// fall back to payload order.
    static func preferredPool(in snapshot: UsageSnapshot) -> OnDemandUsage? {
        let pools = eligiblePools(in: snapshot)
        guard !pools.isEmpty else { return nil }
        return pools.enumerated().min { lhs, rhs in
            let left = rank(lhs.element)
            let right = rank(rhs.element)
            if left != right { return left < right }
            return lhs.offset < rhs.offset
        }?.element
    }

    private static func rank(_ pool: OnDemandUsage) -> Int {
        let hasCapacity = !pool.isUnlimited && pool.remainingFraction != nil
        return (hasCapacity ? 0 : 4) + scopeRank(pool.scope)
    }

    private static func scopeRank(_ scope: OnDemandScope) -> Int {
        switch scope {
        case .personal: 0
        case .team: 1
        case .organization: 2
        }
    }

    // MARK: - Copy

    private static func centerText(
        for pool: OnDemandUsage,
        remainingFraction: Double?
    ) -> String? {
        if remainingFraction != nil, let remaining = pool.remainingAmount {
            return compactAmount(remaining, pool: pool)
        }
        // No capacity to deplete: the honest number is what has been spent.
        guard let used = pool.used, used > 0 else { return nil }
        return compactAmount(used, pool: pool)
    }

    private static func fallbackSymbol(for pool: OnDemandUsage) -> String {
        pool.effectiveUnit == .credits ? "number" : "dollarsign"
    }

    private static func accessibilityDescription(
        for pool: OnDemandUsage,
        remainingFraction: Double?
    ) -> String {
        var values = [pool.label]
        if let remainingFraction, let remaining = pool.remainingAmount {
            values.append("\(amount(remaining, pool: pool)) remaining")
            values.append(
                "\(remainingFraction.formatted(.percent.precision(.fractionLength(0)))) of budget remaining")
        } else if let used = pool.used {
            values.append("\(amount(used, pool: pool)) used")
        } else {
            values.append("No amount reported")
        }
        return values.joined(separator: ", ")
    }

    private static func openRouterAccessibilityDescription(
        provider: ProviderID,
        key: OpenRouterKeyPresentation
    ) -> String {
        var values: [String]
        if let fraction = key.remainingFraction {
            values = [
                "\(provider.displayName) budget",
                "\(key.lockScreenCenterText ?? "No balance reported") remaining",
                "\(fraction.formatted(.percent.precision(.fractionLength(0)))) of budget remaining",
            ]
        } else {
            values = ["\(provider.displayName) pay-as-you-go"]
            if let centerText = key.lockScreenCenterText {
                values.append("Spend today \(centerText)")
            } else {
                values.append("No spend today reported")
            }
        }
        return values.joined(separator: ", ")
    }

    // MARK: - Formatting

    /// Credits are a count, never money: formatting them with a currency symbol
    /// would claim a conversion the provider did not report.
    static func compactAmount(_ value: Double, pool: OnDemandUsage) -> String {
        switch pool.effectiveUnit {
        case .currency:
            return AmountFormat.compactMoney(value, code: pool.currencyCode)
        case .credits:
            return AmountFormat.compactCount(value)
        }
    }

    static func amount(_ value: Double, pool: OnDemandUsage) -> String {
        switch pool.effectiveUnit {
        case .currency:
            return AmountFormat.money(value, code: pool.currencyCode)
        case .credits:
            return "\(AmountFormat.compactCount(value)) credits"
        }
    }
}

/// Shared amount copy for the compact surfaces. Kept in one place so the Lock
/// Screen center reads identically whichever presentation produced it.
enum AmountFormat {
    static func money(_ amount: Double, code: String) -> String {
        amount.formatted(.currency(code: code).precision(.fractionLength(2)))
    }

    /// Whole units stay legible in the tiny gauge center once the amount
    /// reaches two digits. Smaller amounts retain their fractional part.
    static func compactMoney(_ amount: Double, code: String) -> String {
        amount.formatted(
            .currency(code: code)
                .presentation(.narrow)
                .precision(.fractionLength(amount >= 10 ? 0 : 2))
                .locale(Locale(identifier: "en_US")))
    }

    static func compactCount(_ amount: Double) -> String {
        amount.formatted(
            .number
                .precision(.fractionLength(amount >= 10 ? 0 : 2))
                .locale(Locale(identifier: "en_US")))
    }
}
