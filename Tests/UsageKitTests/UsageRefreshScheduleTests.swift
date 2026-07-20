import Foundation
import Testing
@testable import UsageKit

@Suite struct UsageRefreshScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func quietUsageUsesThirtyMinutesEvenWhenCritical() {
        let snapshot = makeSnapshot(remaining: 5, resetAfter: 4 * 3600)
        #expect(UsageRefreshSchedule.nextRefreshDate(snapshots: [snapshot],
                                                     consecutiveUnchangedRefreshes: 2,
                                                     now: now)
            == now.addingTimeInterval(30 * 60))
    }

    @Test func coolsFromFiveToFifteenToThirtyMinutes() {
        let snapshot = makeSnapshot(remaining: 5, resetAfter: 4 * 3600)

        #expect(UsageRefreshSchedule.nextRefreshDate(snapshots: [snapshot],
                                                     consecutiveUnchangedRefreshes: 0,
                                                     now: now)
            == now.addingTimeInterval(5 * 60))
        #expect(UsageRefreshSchedule.nextRefreshDate(snapshots: [snapshot],
                                                     consecutiveUnchangedRefreshes: 1,
                                                     now: now)
            == now.addingTimeInterval(15 * 60))
        #expect(UsageRefreshSchedule.nextRefreshDate(snapshots: [snapshot],
                                                     consecutiveUnchangedRefreshes: 2,
                                                     now: now)
            == now.addingTimeInterval(30 * 60))
    }

    @Test func refreshesAfterAnEarlierKnownReset() {
        let snapshot = makeSnapshot(remaining: 80, resetAfter: 10 * 60)
        #expect(UsageRefreshSchedule.nextRefreshDate(snapshots: [snapshot],
                                                     consecutiveUnchangedRefreshes: 2,
                                                     now: now)
            == now.addingTimeInterval(10 * 60 + 30))
    }

    @Test func neverRequestsCloserThanFiveMinutes() {
        let snapshot = makeSnapshot(remaining: 80, resetAfter: 60)
        #expect(UsageRefreshSchedule.nextRefreshDate(snapshots: [snapshot],
                                                     consecutiveUnchangedRefreshes: 2,
                                                     now: now)
            == now.addingTimeInterval(5 * 60))
    }

    @Test func missingSnapshotsUseQuietDefault() {
        #expect(UsageRefreshSchedule.nextRefreshDate(snapshots: [], now: now)
            == now.addingTimeInterval(30 * 60))
    }

    @Test func detectsUsageMovementWithoutTreatingFetchTimeAsMovement() {
        let previous = makeSnapshot(remaining: 80, resetAfter: 4 * 3600)
        let sameUsage = UsageSnapshot(provider: previous.provider,
                                      plan: previous.plan,
                                      windows: previous.windows,
                                      fetchedAt: now.addingTimeInterval(60))
        let changed = makeSnapshot(remaining: 79, resetAfter: 4 * 3600)

        #expect(!UsageRefreshSchedule.usageChanged(from: nil, to: previous))
        #expect(!UsageRefreshSchedule.usageChanged(from: previous, to: sameUsage))
        #expect(UsageRefreshSchedule.usageChanged(from: previous, to: changed))
        #expect(UsageRefreshSchedule.nextUnchangedRefreshCount(
            previousCount: 2, previousSnapshot: previous, currentSnapshot: changed) == 0)
        #expect(UsageRefreshSchedule.nextUnchangedRefreshCount(
            previousCount: 0, previousSnapshot: previous, currentSnapshot: sameUsage) == 1)
        #expect(UsageRefreshSchedule.nextUnchangedRefreshCount(
            previousCount: 1, previousSnapshot: previous, currentSnapshot: sameUsage) == 2)
    }

    private func makeSnapshot(remaining: Double, resetAfter: TimeInterval) -> UsageSnapshot {
        UsageSnapshot(provider: .claude,
                      plan: nil,
                      windows: [
                        LimitWindow(kind: .session,
                                    label: "Session",
                                    usedPercent: 100 - remaining,
                                    resetsAt: now.addingTimeInterval(resetAfter)),
                      ],
                      fetchedAt: now)
    }
}
