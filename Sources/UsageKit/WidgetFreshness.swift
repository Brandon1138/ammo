import Foundation

/// Freshness bookkeeping for the shared usage cache.
///
/// The app writes the cache; the widget extension only ever reads it. Neither
/// process can observe the other's memory, so the only way to tell "the widget
/// is rendering what the app just wrote" apart from "the widget never received
/// the write" is to stamp every committed cache write with a monotonically
/// increasing revision and republish it beside the cache. Both processes log
/// the revision they wrote or read, which turns an unverifiable timing bug into
/// two log lines that either agree or do not.
public struct SharedStoreRevision: Codable, Sendable, Equatable {
    /// Increases by one per committed write. Wrap-around is not modelled: at one
    /// write per second it would take longer than the heat death of the sun.
    public var revision: UInt64
    /// When the writer finished committing the cache file, not when it fetched.
    public var writtenAt: Date
    /// Shape of the payload the revision describes, so a log line alone shows
    /// whether the widget is reading an empty cache or a populated one.
    public var accountCount: Int
    public var snapshotCount: Int
    /// Newest `fetchedAt` across the written snapshots — the value a widget's
    /// "Updated … ago" would reference.
    public var newestSnapshotAt: Date?

    public init(
        revision: UInt64,
        writtenAt: Date,
        accountCount: Int,
        snapshotCount: Int,
        newestSnapshotAt: Date?
    ) {
        self.revision = revision
        self.writtenAt = writtenAt
        self.accountCount = accountCount
        self.snapshotCount = snapshotCount
        self.newestSnapshotAt = newestSnapshotAt
    }

    /// The revision that supersedes `previous`. A missing or unreadable previous
    /// revision restarts at 1 rather than failing the write it describes.
    public static func next(
        after previous: SharedStoreRevision?,
        writtenAt: Date,
        accountCount: Int,
        snapshotCount: Int,
        newestSnapshotAt: Date?
    ) -> SharedStoreRevision {
        SharedStoreRevision(
            revision: (previous?.revision ?? 0) &+ 1,
            writtenAt: writtenAt,
            accountCount: accountCount,
            snapshotCount: snapshotCount,
            newestSnapshotAt: newestSnapshotAt)
    }

    /// Compact, non-sensitive description for os_log. Counts and dates only —
    /// no labels, no provider identity, nothing account-specific.
    public var logDescription: String {
        let newest = newestSnapshotAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none"
        return "rev=\(revision) writtenAt=\(ISO8601DateFormatter().string(from: writtenAt))"
            + " accounts=\(accountCount) snapshots=\(snapshotCount) newestSnapshot=\(newest)"
    }
}

/// Entry dates for a widget timeline.
///
/// Entries exist only to advance locally computable display state — countdowns
/// to a reset, and the switch to the conservative "reset due" treatment once a
/// boundary passes. They carry no new provider data, so more of them buys
/// nothing while costing archive size in a process WidgetKit is willing to
/// terminate. The schedule is therefore coarse and hard-bounded.
public enum WidgetTimelinePlan {
    /// Upper bound on entries handed to WidgetKit in one timeline.
    public static let maximumEntries = 64
    /// How far ahead entries are pre-computed when WidgetKit never comes back.
    public static let horizon: TimeInterval = 8 * 24 * 60 * 60

    public static func dates(
        resetDates: [Date],
        now: Date = Date(),
        limit: Int = maximumEntries
    ) -> [Date] {
        precondition(limit >= 1, "A timeline needs at least the current entry")

        var gridDates: Set<Date> = [now]
        appendSteps(into: &gridDates, from: now, until: now.addingTimeInterval(2 * 3600),
                    step: 15 * 60, after: now)
        appendSteps(into: &gridDates, from: now.addingTimeInterval(2 * 3600),
                    until: now.addingTimeInterval(24 * 3600), step: 60 * 60, after: now)
        appendSteps(into: &gridDates, from: now.addingTimeInterval(24 * 3600),
                    until: now.addingTimeInterval(horizon), step: 6 * 3600, after: now)

        let horizonEnd = now.addingTimeInterval(horizon)
        let resetBoundaries = Set(resetDates.filter { $0 > now && $0 <= horizonEnd })
        var requiredDates = resetBoundaries
        requiredDates.insert(now)

        // Reset boundaries carry state transitions; grid entries only improve
        // countdown resolution. Reserve every boundary first, then spend the
        // remaining budget on nearest grid entries. If boundaries alone exceed
        // WidgetKit's hard cap, retain `now` and the earliest reachable resets.
        let sortedRequired = requiredDates.sorted()
        guard sortedRequired.count < limit else {
            return Array(sortedRequired.prefix(limit))
        }

        gridDates.subtract(requiredDates)
        let gridSlots = limit - sortedRequired.count
        let selectedGrid = gridDates.sorted().prefix(gridSlots)
        return (sortedRequired + selectedGrid).sorted()
    }

    private static func appendSteps(
        into dates: inout Set<Date>,
        from start: Date,
        until end: Date,
        step: TimeInterval,
        after now: Date
    ) {
        var next = start.addingTimeInterval(step)
        while next <= end {
            if next > now { dates.insert(next) }
            next = next.addingTimeInterval(step)
        }
    }
}
