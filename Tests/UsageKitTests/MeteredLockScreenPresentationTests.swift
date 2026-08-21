import Foundation
import Testing
@testable import UsageKit

/// The Lock Screen gauge for accounts whose provider reports spend instead of a
/// percentage window. Cursor is the case that regressed: `usage-summary` omits
/// the `individualUsage.plan` block for team and enterprise members and for
/// usage-based plans, so those snapshots carry on-demand pools and no windows.
@Suite struct MeteredLockScreenPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func cursorTeamMemberWithoutWindowsStillDrawsALiveGauge() throws {
        let snapshot = cursorSnapshot(pools: [
            pool(id: "cursor-personal-allocation",
                 label: "Personal allocation",
                 kind: .personalAllocation,
                 scope: .personal,
                 used: 30,
                 limit: 120),
        ])

        // The window gauge has nothing to select, which is what used to drop
        // Cursor onto the static dollar glyph.
        #expect(LockScreenUsagePresentation(snapshot: snapshot) == nil)

        let presentation = try #require(MeteredLockScreenPresentation(snapshot: snapshot))
        #expect(presentation.pool.id == "cursor-personal-allocation")
        #expect(presentation.remainingFraction == 0.75)
        #expect(presentation.centerText == AmountFormat.compactMoney(90, code: "USD"))
        #expect(presentation.centerFallbackSymbol == "dollarsign")
        #expect(presentation.fetchedAt == now)
    }

    @Test func amountOnlyPoolPrintsSpendAndOffersNoCapacity() throws {
        let snapshot = cursorSnapshot(pools: [
            pool(id: "cursor-personal-on-demand",
                 label: "Personal on-demand",
                 kind: .spendingLimit,
                 scope: .personal,
                 isUnlimited: true,
                 used: 12.5),
        ])

        let presentation = try #require(MeteredLockScreenPresentation(snapshot: snapshot))
        #expect(presentation.remainingFraction == nil)
        #expect(presentation.centerText == AmountFormat.compactMoney(12.5, code: "USD"))
    }

    @Test func aPoolWithCapacityOutranksAnAmountOnlyPoolListedBefore() throws {
        let snapshot = cursorSnapshot(pools: [
            pool(id: "cursor-personal-on-demand",
                 label: "Personal on-demand",
                 kind: .spendingLimit,
                 scope: .personal,
                 isUnlimited: true,
                 used: 4),
            pool(id: "cursor-personal-allocation",
                 label: "Personal allocation",
                 kind: .personalAllocation,
                 scope: .personal,
                 used: 20,
                 limit: 100),
        ])

        let presentation = try #require(MeteredLockScreenPresentation(snapshot: snapshot))
        #expect(presentation.pool.id == "cursor-personal-allocation")
        #expect(presentation.remainingFraction == 0.8)
    }

    @Test func thePersonsOwnMeterOutranksASharedTeamBudget() throws {
        let snapshot = cursorSnapshot(pools: [
            pool(id: "cursor-team-on-demand",
                 label: "Team on-demand",
                 kind: .teamBudget,
                 scope: .team,
                 used: 10,
                 limit: 100),
            pool(id: "cursor-personal-allocation",
                 label: "Personal allocation",
                 kind: .personalAllocation,
                 scope: .personal,
                 used: 60,
                 limit: 100),
        ])

        let presentation = try #require(MeteredLockScreenPresentation(snapshot: snapshot))
        #expect(presentation.pool.scope == .personal)
    }

    @Test func poolsTheProviderReportedAsDisabledAreNeverDrawn() {
        let snapshot = cursorSnapshot(pools: [
            pool(id: "cursor-personal-on-demand",
                 label: "Personal on-demand",
                 kind: .spendingLimit,
                 scope: .personal,
                 isEnabled: false,
                 used: 40,
                 limit: 100),
        ])

        #expect(MeteredLockScreenPresentation(snapshot: snapshot) == nil)
    }

    @Test func aSnapshotWithNoPoolsAtAllPresentsNothing() {
        #expect(MeteredLockScreenPresentation(snapshot: cursorSnapshot(pools: [])) == nil)
        #expect(MeteredLockScreenPresentation(
            snapshot: UsageSnapshot(provider: .cursor, plan: "pro", windows: [], fetchedAt: now)) == nil)
    }

    @Test func creditBalancesAreNeverFormattedAsMoney() throws {
        let snapshot = UsageSnapshot(
            provider: .codex,
            plan: "plus",
            windows: [],
            onDemand: [
                OnDemandUsage(id: "codex-usage-credits",
                              label: "Usage credits",
                              kind: .creditBalance,
                              scope: .personal,
                              isEnabled: true,
                              unit: .credits,
                              used: 25,
                              limit: 100,
                              remaining: 75),
            ],
            fetchedAt: now)

        let presentation = try #require(MeteredLockScreenPresentation(snapshot: snapshot))
        #expect(presentation.centerFallbackSymbol == "number")
        #expect(presentation.centerText == "75")
        #expect(presentation.centerText?.contains("$") == false)
    }

    @Test func openRouterKeepsTheGaugeItsOwnPresentationProduces() throws {
        let snapshot = UsageSnapshot(
            provider: .openRouter,
            plan: nil,
            windows: [],
            onDemand: [
                OnDemandUsage(id: OpenRouterKeyPresentation.spendingPoolID,
                              label: "API key spending",
                              kind: .spendingLimit,
                              scope: .personal,
                              isEnabled: true,
                              used: 25.5,
                              limit: 100,
                              remaining: 74.5,
                              periodStart: now.addingTimeInterval(-18 * 86_400),
                              resetsAt: now.addingTimeInterval(12 * 86_400)),
            ],
            fetchedAt: now)

        let key = try #require(OpenRouterKeyPresentation(snapshot: snapshot))
        let presentation = try #require(MeteredLockScreenPresentation(snapshot: snapshot))

        #expect(presentation.remainingFraction == key.remainingFraction)
        #expect(presentation.centerText == key.lockScreenCenterText)
    }

    @Test func openRouterPayAsYouGoStillCentersTodaysSpend() throws {
        let snapshot = UsageSnapshot(
            provider: .openRouter,
            plan: nil,
            windows: [],
            onDemand: [
                OnDemandUsage(id: OpenRouterKeyPresentation.spendingPoolID,
                              label: "API key spending",
                              kind: .spendingLimit,
                              scope: .personal,
                              isEnabled: true,
                              isUnlimited: true,
                              used: 140),
                OnDemandUsage(id: OpenRouterKeyPresentation.dailyPoolID,
                              label: "Spend today",
                              kind: .spendingLimit,
                              scope: .personal,
                              isEnabled: true,
                              isUnlimited: true,
                              used: 3.25),
            ],
            fetchedAt: now)

        let presentation = try #require(MeteredLockScreenPresentation(snapshot: snapshot))
        #expect(presentation.remainingFraction == nil)
        #expect(presentation.centerText == AmountFormat.compactMoney(3.25, code: "USD"))
    }

    @Test func aCursorSnapshotThatKeepsItsWindowsNeverNeedsTheSpendGauge() throws {
        let snapshot = UsageSnapshot(
            provider: .cursor,
            plan: "pro",
            windows: [
                LimitWindow(kind: .monthly, label: "Composer", usedPercent: 99, resetsAt: nil),
                LimitWindow(kind: .monthly, label: "API", usedPercent: 81, resetsAt: nil),
            ],
            onDemand: [
                pool(id: "cursor-personal-on-demand",
                     label: "Personal on-demand",
                     kind: .spendingLimit,
                     scope: .personal,
                     used: 4,
                     limit: 50),
            ],
            fetchedAt: now)

        let windows = try #require(LockScreenUsagePresentation(snapshot: snapshot))
        #expect(windows.indicatorWindow.label == "Composer")
        #expect(windows.numericWindow?.label == "API")
    }

    // MARK: - Fixtures

    private func cursorSnapshot(pools: [OnDemandUsage]) -> UsageSnapshot {
        UsageSnapshot(provider: .cursor,
                      plan: "pro",
                      windows: [],
                      onDemand: pools.isEmpty ? nil : pools,
                      fetchedAt: now)
    }

    private func pool(
        id: String,
        label: String,
        kind: OnDemandKind,
        scope: OnDemandScope,
        isEnabled: Bool = true,
        isUnlimited: Bool = false,
        used: Double? = nil,
        limit: Double? = nil
    ) -> OnDemandUsage {
        OnDemandUsage(id: id,
                      label: label,
                      kind: kind,
                      scope: scope,
                      isEnabled: isEnabled,
                      isUnlimited: isUnlimited,
                      used: used,
                      limit: limit,
                      periodStart: now.addingTimeInterval(-10 * 86_400),
                      resetsAt: now.addingTimeInterval(20 * 86_400))
    }
}
