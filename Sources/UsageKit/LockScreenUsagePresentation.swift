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
        guard let firstWindow = snapshot.windows.first else { return nil }

        let indicator = snapshot.windows.first { $0.kind == .session } ?? firstWindow
        let remaining = snapshot.windows.filter { $0.id != indicator.id }
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
