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

    @Test func refreshesAfterAnOnDemandBillingBoundary() {
        let snapshot = UsageSnapshot(
            provider: .cursor,
            plan: "enterprise",
            windows: [],
            onDemand: [
                OnDemandUsage(id: "cursor-shared-pool",
                              label: "Shared pool",
                              kind: .pooledBudget,
                              scope: .organization,
                              isEnabled: true,
                              used: 1_200,
                              limit: 5_000,
                              remaining: 3_800,
                              resetsAt: now.addingTimeInterval(10 * 60)),
            ],
            fetchedAt: now)

        #expect(UsageRefreshSchedule.nextRefreshDate(snapshots: [snapshot],
                                                     consecutiveUnchangedRefreshes: 2,
                                                     now: now)
            == now.addingTimeInterval(10 * 60 + 30))
    }

    @Test func missingSnapshotsRetryAtActiveInterval() {
        #expect(UsageRefreshSchedule.nextRefreshDate(snapshots: [], now: now)
            == now.addingTimeInterval(5 * 60))
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

    @Test func detectsOnDemandSpendMovement() {
        let window = LimitWindow(kind: .weekly,
                                 label: "Weekly",
                                 usedPercent: 100,
                                 resetsAt: now.addingTimeInterval(4 * 3600))
        let previous = UsageSnapshot(
            provider: .codex,
            plan: "plus",
            windows: [window],
            onDemand: [
                OnDemandUsage(id: "codex-usage-credits",
                              label: "Usage credits",
                              kind: .creditBalance,
                              scope: .personal,
                              isEnabled: true,
                              remaining: 20),
            ],
            fetchedAt: now)
        let current = UsageSnapshot(
            provider: .codex,
            plan: "plus",
            windows: [window],
            onDemand: [
                OnDemandUsage(id: "codex-usage-credits",
                              label: "Usage credits",
                              kind: .creditBalance,
                              scope: .personal,
                              isEnabled: true,
                              remaining: 19.5),
            ],
            fetchedAt: now.addingTimeInterval(60))

        #expect(UsageRefreshSchedule.usageChanged(from: previous, to: current))
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
