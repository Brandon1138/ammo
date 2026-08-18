import Foundation
import Testing

@testable import UsageKit

@Suite("Widget freshness bookkeeping (MIK-110, MIK-51)")
struct WidgetFreshnessTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Shared cache revision

    @Test("The first revision starts at one rather than failing on a missing predecessor")
    func firstRevision() {
        let revision = SharedStoreRevision.next(
            after: nil,
            writtenAt: now,
            accountCount: 2,
            snapshotCount: 1,
            newestSnapshotAt: now)

        #expect(revision.revision == 1)
        #expect(revision.accountCount == 2)
        #expect(revision.snapshotCount == 1)
    }

    @Test("Each committed write supersedes the previous revision")
    func revisionIncrements() {
        var revision = SharedStoreRevision.next(
            after: nil, writtenAt: now, accountCount: 1,
            snapshotCount: 0, newestSnapshotAt: nil)

        for expected in UInt64(2)...5 {
            revision = SharedStoreRevision.next(
                after: revision,
                writtenAt: now,
                accountCount: 1,
                snapshotCount: 1,
                newestSnapshotAt: now)
            #expect(revision.revision == expected)
        }
    }

    @Test("A revision survives the shared cache codec so both processes read the same value")
    func revisionRoundTrips() throws {
        let revision = SharedStoreRevision(
            revision: 42,
            writtenAt: now,
            accountCount: 4,
            snapshotCount: 3,
            newestSnapshotAt: now.addingTimeInterval(-90))

        let data = try UsageCacheCodec.encode(revision)
        let decoded = try UsageCacheCodec.decode(SharedStoreRevision.self, from: data)

        #expect(decoded == revision)
    }

    @Test("The log description carries counts and timestamps, never account identity")
    func revisionLogDescription() {
        let description = SharedStoreRevision(
            revision: 7, writtenAt: now, accountCount: 4,
            snapshotCount: 4, newestSnapshotAt: now).logDescription

        #expect(description.contains("rev=7"))
        #expect(description.contains("accounts=4"))
        #expect(description.contains("snapshots=4"))
        #expect(description.contains("newestSnapshot="))
    }

    @Test("A cache with no snapshot yet reports no newest snapshot")
    func revisionWithoutSnapshots() {
        let revision = SharedStoreRevision.next(
            after: nil, writtenAt: now, accountCount: 3,
            snapshotCount: 0, newestSnapshotAt: nil)

        #expect(revision.newestSnapshotAt == nil)
        #expect(revision.logDescription.contains("newestSnapshot=none"))
    }

    // MARK: - Timeline plan

    @Test("A timeline never exceeds its entry bound")
    func planIsBounded() {
        let resets = (1...40).map { now.addingTimeInterval(Double($0) * 3600) }
        let dates = WidgetTimelinePlan.dates(resetDates: resets, now: now)

        #expect(dates.count <= WidgetTimelinePlan.maximumEntries)
        #expect(dates.count > 1)
    }

    @Test("The current moment is always the first entry")
    func planStartsNow() {
        let dates = WidgetTimelinePlan.dates(resetDates: [], now: now)

        #expect(dates.first == now)
        #expect(dates == dates.sorted())
    }

    @Test("Entries are unique so WidgetKit never receives a duplicate date")
    func planIsDeduplicated() {
        // A reset that lands exactly on a grid step must not appear twice.
        let onGrid = now.addingTimeInterval(15 * 60)
        let dates = WidgetTimelinePlan.dates(resetDates: [onGrid, onGrid], now: now)

        #expect(Set(dates).count == dates.count)
    }

    @Test("Reset boundaries inside the horizon become their own entries")
    func planIncludesResets() {
        let reset = now.addingTimeInterval(3 * 3600 + 137)
        let dates = WidgetTimelinePlan.dates(resetDates: [reset], now: now)

        #expect(dates.contains(reset))
    }

    @Test("Reset boundaries survive the entry cap before grid density")
    func resetBoundariesSurviveCap() {
        let resets = (1...40).map { offset in
            // Distinct off-grid boundaries spread across the full horizon.
            now.addingTimeInterval(Double(offset) * 4 * 3600 + Double(offset))
        }
        let dates = WidgetTimelinePlan.dates(resetDates: resets, now: now)

        #expect(dates.count == WidgetTimelinePlan.maximumEntries)
        #expect(resets.count == 40)
        #expect(Set(resets).isSubset(of: Set(dates)))
    }

    @Test("Past resets and resets beyond the horizon are ignored")
    func planIgnoresOutOfRangeResets() {
        let past = now.addingTimeInterval(-3600)
        let beyond = now.addingTimeInterval(WidgetTimelinePlan.horizon + 3600)
        let dates = WidgetTimelinePlan.dates(resetDates: [past, beyond], now: now)

        #expect(!dates.contains(past))
        #expect(!dates.contains(beyond))
    }

    @Test("Countdown resolution stays fine near now and coarsens further out")
    func planResolution() {
        let dates = WidgetTimelinePlan.dates(resetDates: [], now: now)
        let withinTwoHours = dates.filter { $0 <= now.addingTimeInterval(2 * 3600) }

        // Quarter-hour steps across the first two hours, plus `now` itself.
        #expect(withinTwoHours.count == 9)
        #expect(dates.last ?? now > now.addingTimeInterval(24 * 3600))
    }

    @Test("An explicit limit of one yields only the current entry")
    func planHonorsTightLimit() {
        #expect(WidgetTimelinePlan.dates(resetDates: [], now: now, limit: 1) == [now])
    }
}
