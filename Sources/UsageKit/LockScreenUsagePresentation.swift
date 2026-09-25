import Foundation

/// Provider-neutral selection for the two values that fit in a Lock Screen
/// circular widget. Every displayed value comes from a provider-reported
/// window; no provider is assigned a synthetic short window.
public struct LockScreenUsagePresentation: Sendable, Equatable {
    public static let staleAfter = UsageRefreshSchedule.quietInterval * 2

    public let indicatorWindow: LimitWindow
    public let numericWindow: LimitWindow?
    public let fetchedAt: Date

    public init?(snapshot: UsageSnapshot) {
        // Model-scoped buckets (such as Claude's Fable) are extra meters,
        // not the account's headline limits. Left in the pool they could
        // claim the numeric slot when a provider reports one included window.
        let headline = snapshot.windows.filter { $0.kind != .modelScoped }
        let pool = headline.isEmpty ? snapshot.windows : headline
        guard let firstWindow = pool.first else { return nil }

        let indicator = pool.first { $0.kind == .session } ?? firstWindow
        let remaining = pool.filter { $0.id != indicator.id }
        let numeric = remaining.first { $0.kind == .weekly } ?? remaining.first

        indicatorWindow = indicator
        numericWindow = numeric
        fetchedAt = snapshot.fetchedAt
    }

    public func isStale(
        at referenceDate: Date,
        staleAfter threshold: TimeInterval = Self.staleAfter
    ) -> Bool {
        referenceDate.timeIntervalSince(fetchedAt) > threshold
    }
}
