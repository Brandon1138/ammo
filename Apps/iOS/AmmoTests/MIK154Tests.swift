import Foundation
import Testing
import UsageKit

@testable import Ammo

/// MIK-154: the Cursor Lock Screen gauge.
///
/// Cursor is the only shipping provider that can report spend without any
/// percentage window — `usage-summary` omits `individualUsage.plan` for team
/// and enterprise members and for usage-based plans. In that state the Lock
/// Screen fell through to an OpenRouter-only branch and then to a static
/// `ProviderLogo` + dollar-glyph stack that was bound to no snapshot value, so
/// it could never change no matter how fresh the timeline was.
@MainActor
@Suite("MIK-154 Cursor Lock Screen gauge")
struct MIK154Tests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("A windowless Cursor account gets a live spend gauge, not a static glyph")
    func cursorWithoutWindowsDrawsTheSpendGauge() throws {
        let state = cursorState(windows: [], pools: [personalAllocation(used: 30, limit: 120)])

        #expect(state.lockScreenUsagePresentation == nil)
        #expect(state.hasWidgetMeteredUsage)

        let metered = try #require(state.lockScreenMeteredPresentation)
        #expect(metered.pool.id == "cursor-personal-allocation")
        #expect(metered.remainingFraction == 0.75)
        #expect(metered.centerText != nil)
    }

    @Test("The gauge value tracks the snapshot rather than staying put")
    func theGaugeValueFollowsTheCache() throws {
        let first = try #require(cursorState(
            windows: [], pools: [personalAllocation(used: 30, limit: 120)])
            .lockScreenMeteredPresentation)
        let later = try #require(cursorState(
            windows: [], pools: [personalAllocation(used: 90, limit: 120)])
            .lockScreenMeteredPresentation)

        #expect(first.remainingFraction != later.remainingFraction)
        #expect(later.remainingFraction == 0.25)
    }

    @Test("A Cursor account with Cursor Models and Other Models keeps the window gauge")
    func cursorWithWindowsKeepsTheWindowGauge() throws {
        let state = cursorState(
            windows: [
                LimitWindow(kind: .monthly,
                            label: CursorProvider.cursorModelsLabel,
                            usedPercent: 99,
                            resetsAt: nil),
                LimitWindow(kind: .monthly,
                            label: CursorProvider.otherModelsLabel,
                            usedPercent: 81,
                            resetsAt: nil),
            ],
            pools: [personalAllocation(used: 30, limit: 120)])

        let presentation = try #require(state.lockScreenUsagePresentation)
        #expect(presentation.indicatorWindow.label == CursorProvider.cursorModelsLabel)
        #expect(presentation.numericWindow?.label == CursorProvider.otherModelsLabel)
    }

    @Test("Recovered Cursor windows survive the shared cache path used by circular")
    func recoveredCursorWindowsSurviveWidgetCacheRoundTrip() throws {
        let account = StoredAccount(provider: .cursor, label: "Cursor Enterprise")
        let snapshot = UsageSnapshot(
            provider: .cursor,
            plan: "enterprise",
            windows: [
                LimitWindow(kind: .monthly,
                            label: CursorProvider.cursorModelsLabel,
                            usedPercent: 42,
                            resetsAt: now.addingTimeInterval(12 * 86_400)),
                LimitWindow(kind: .monthly,
                            label: CursorProvider.otherModelsLabel,
                            usedPercent: 7,
                            resetsAt: now.addingTimeInterval(12 * 86_400)),
            ],
            onDemand: [personalAllocation(used: 30, limit: 120)],
            fetchedAt: now)
        let state = AccountState(account: account,
                                 snapshot: snapshot,
                                 lastError: nil,
                                 updatedAt: now)

        let cached = try UsageCacheCodec.encode([state])
        let restored = try UsageCacheCodec.decode([AccountState].self, from: cached)
        let restoredState = try #require(restored.first)
        let presentation = try #require(restoredState.lockScreenUsagePresentation)

        #expect(restoredState.snapshot?.windows.map(\.label) == [
            CursorProvider.cursorModelsLabel,
            CursorProvider.otherModelsLabel,
        ])
        #expect(presentation.indicatorWindow.label == CursorProvider.cursorModelsLabel)
        #expect(presentation.numericWindow?.label == CursorProvider.otherModelsLabel)
    }

    @Test("A windowless cached Cursor snapshot recovers from its retained MIK-159 response")
    func windowlessCacheRecoversDisplayMessageWindows() throws {
        let stale = UsageSnapshot(
            provider: .cursor,
            plan: "enterprise",
            windows: [],
            onDemand: [personalAllocation(used: 30, limit: 120)],
            fetchedAt: now)
        let response = Data(#"""
        {
          "billingCycleEnd": "2026-08-10T00:00:00Z",
          "membershipType": "enterprise",
          "autoModelSelectedDisplayMessage": "You've used 42% of your included total usage",
          "namedModelSelectedDisplayMessage": "You've used 7% of your API usage"
        }
        """#.utf8)

        let repaired = SharedStore.recoverCursorWindows(
            in: stale, rawPayload: response, fetchedAt: now)
        let state = AccountState(
            account: StoredAccount(provider: .cursor, label: "Cursor Enterprise"),
            snapshot: repaired,
            lastError: nil,
            updatedAt: now)
        let presentation = try #require(state.lockScreenUsagePresentation)

        #expect(repaired.windows.map(\.label) == [
            CursorProvider.cursorModelsLabel,
            CursorProvider.otherModelsLabel,
        ])
        #expect(presentation.indicatorWindow.label == CursorProvider.cursorModelsLabel)
        #expect(presentation.numericWindow?.label == CursorProvider.otherModelsLabel)
    }

    @Test("OpenRouter keeps the gauge its own key presentation produces")
    func openRouterGaugeIsUnchanged() throws {
        let pool = OnDemandUsage(
            id: OpenRouterKeyPresentation.spendingPoolID,
            label: "API key spending",
            kind: .spendingLimit,
            scope: .personal,
            isEnabled: true,
            used: 25.5,
            limit: 100,
            remaining: 74.5,
            periodStart: now.addingTimeInterval(-18 * 86_400),
            resetsAt: now.addingTimeInterval(12 * 86_400))
        let snapshot = UsageSnapshot(
            provider: .openRouter, plan: nil, windows: [], onDemand: [pool], fetchedAt: now)
        let state = AccountState(
            account: StoredAccount(provider: .openRouter, label: "OpenRouter"),
            snapshot: snapshot,
            lastError: nil,
            updatedAt: now)

        let key = try #require(OpenRouterKeyPresentation(snapshot: snapshot))
        let metered = try #require(state.lockScreenMeteredPresentation)

        #expect(metered.remainingFraction == key.remainingFraction)
        #expect(metered.centerText == key.lockScreenCenterText)
    }

    @Test("An account with neither windows nor pools presents no gauge at all")
    func emptyAccountStillHasNoGauge() {
        let state = cursorState(windows: [], pools: [])

        #expect(state.lockScreenUsagePresentation == nil)
        #expect(state.lockScreenMeteredPresentation == nil)
        #expect(!state.hasWidgetMeteredUsage)
    }

    // MARK: - Fixtures

    private func cursorState(
        windows: [LimitWindow],
        pools: [OnDemandUsage]
    ) -> AccountState {
        AccountState(
            account: StoredAccount(provider: .cursor, label: "Cursor"),
            snapshot: UsageSnapshot(provider: .cursor,
                                    plan: "enterprise",
                                    windows: windows,
                                    onDemand: pools.isEmpty ? nil : pools,
                                    fetchedAt: now),
            lastError: nil,
            updatedAt: now)
    }

    private func personalAllocation(used: Double, limit: Double) -> OnDemandUsage {
        OnDemandUsage(id: "cursor-personal-allocation",
                      label: "Personal allocation",
                      kind: .personalAllocation,
                      scope: .personal,
                      isEnabled: true,
                      used: used,
                      limit: limit,
                      periodStart: now.addingTimeInterval(-10 * 86_400),
                      resetsAt: now.addingTimeInterval(20 * 86_400))
    }
}
