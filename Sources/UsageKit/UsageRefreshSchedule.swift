import Foundation

/// Provider-neutral cadence used by both BGAppRefreshTask and WidgetKit.
/// These are requested dates only; the operating system may run later.
public enum UsageRefreshSchedule {
    public static let minimumInterval: TimeInterval = 5 * 60
    public static let activeInterval: TimeInterval = 5 * 60
    public static let coolingInterval: TimeInterval = 15 * 60
    public static let quietInterval: TimeInterval = 30 * 60

    public static func nextRefreshDate(
        snapshots: [UsageSnapshot],
        consecutiveUnchangedRefreshes: Int = 2,
        now: Date = Date()
    ) -> Date {
        // Missing first snapshot is active work, not quiet usage. Retrying at
        // normal active cadence avoids stranding failed initial fetches behind
        // 30-minute steady-state interval.
        guard !snapshots.isEmpty else {
            return now.addingTimeInterval(activeInterval)
        }

        let windows = snapshots.flatMap(\.windows)
        let activityInterval: TimeInterval
        switch consecutiveUnchangedRefreshes {
        case ..<1:
            activityInterval = activeInterval
        case 1:
            activityInterval = coolingInterval
        default:
            activityInterval = quietInterval
        }

        let activityDate = Date(timeInterval: activityInterval, since: now)
        let minimumDate = Date(timeInterval: minimumInterval, since: now)
        let onDemand = snapshots.flatMap { $0.onDemand ?? [] }
        let nextResetDate = (windows.compactMap(\.resetsAt)
            + onDemand.compactMap(\.resetsAt)
            + onDemand.compactMap(\.expiresAt))
            .filter { $0 > now }
            .min()
            .map { Date(timeInterval: 30, since: $0) }

        // Refresh soon after a known rollover when it is earlier than the
        // activity cadence, while avoiding requests closer than WidgetKit's
        // practical minimum interval. Low remaining usage alone never pins an
        // inactive account to the five-minute cadence.
        return max(minimumDate, min(activityDate, nextResetDate ?? activityDate))
    }

    /// Usage changed when a provider-reported value, reset boundary, or reset
    /// credit changed. `fetchedAt` is deliberately ignored.
    public static func usageChanged(from previous: UsageSnapshot?, to current: UsageSnapshot) -> Bool {
        guard let previous else { return false }
        guard previous.provider == current.provider,
              previous.resetCreditsAvailable == current.resetCreditsAvailable,
              previous.onDemand == current.onDemand,
              previous.windows.count == current.windows.count else { return true }

        let previousByID = Dictionary(uniqueKeysWithValues: previous.windows.map { ($0.id, $0) })
        return current.windows.contains { window in
            guard let old = previousByID[window.id] else { return true }
            return abs(old.usedPercent - window.usedPercent) > 0.001
                || old.resetsAt != window.resetsAt
        }
    }

    public static func nextUnchangedRefreshCount(
        previousCount: Int,
        previousSnapshot: UsageSnapshot?,
        currentSnapshot: UsageSnapshot
    ) -> Int {
        guard previousSnapshot != nil else { return 1 }
        return usageChanged(from: previousSnapshot, to: currentSnapshot)
            ? 0
            : min(2, previousCount + 1)
    }
}
