import Foundation
import Testing
import UsageKit
@testable import Ammo

/// The History screen used to render its account selector *inside* the
/// window-charting branch, so an account without a limit window (Codex Business,
/// a failed first refresh, a malformed response) replaced the whole screen with
/// "No usage limits" and removed every way to switch account or provider.
/// These tests pin the resolution rules that keep the selector reachable.
@MainActor
@Suite("History selection cannot trap the user")
struct HistorySelectionTests {
    private static func state(
        label: String = "Account",
        provider: ProviderID = .codex,
        snapshot: UsageSnapshot?,
        failure: UsageFailureKind? = nil
    ) -> AccountState {
        AccountState(
            account: StoredAccount(provider: provider, label: label),
            snapshot: snapshot,
            lastError: nil,
            lastFailure: failure,
            updatedAt: snapshot?.fetchedAt)
    }

    private static func snapshot(windows: [LimitWindow]) -> UsageSnapshot {
        UsageSnapshot(provider: .codex, plan: "plus", windows: windows)
    }

    private static let weekly = LimitWindow(
        kind: .weekly, label: "Weekly", usedPercent: 40, resetsAt: nil)
    private static let monthly = LimitWindow(
        kind: .monthly, label: "Monthly", usedPercent: 10, resetsAt: nil)

    @Test("A zero-window snapshot still resolves an account to select")
    func zeroWindowSnapshotKeepsSelectorState() {
        let business = Self.state(label: "Codex Business",
                                  snapshot: Self.snapshot(windows: []))
        let states = [business]

        let resolved = HistoryView.resolveState(
            in: states, selection: HistorySelection(accountID: business.id))

        #expect(resolved?.id == business.id)
        #expect(HistoryView.windowContent(
            for: business,
            selection: HistorySelection(accountID: business.id)) == .noLimitWindows)
    }

    @Test("A nil snapshot reports awaiting rather than no limits")
    func nilSnapshotAwaitsData() {
        let pending = Self.state(snapshot: nil)

        #expect(HistoryView.windowContent(
            for: pending, selection: HistorySelection()) == .awaitingSnapshot)
    }

    @Test("A refresh failure without a snapshot still resolves the account")
    func failedRefreshKeepsSelectorState() {
        let failed = Self.state(snapshot: nil, failure: .invalidResponse)
        let states = [failed]

        #expect(HistoryView.resolveState(
            in: states, selection: HistorySelection(accountID: failed.id))?.id == failed.id)
        #expect(HistoryView.windowContent(
            for: failed, selection: HistorySelection()) == .awaitingSnapshot)
        #expect(failed.activeFailure == .invalidResponse)
    }

    @Test("Switching to a zero-window account does not fall back to another account")
    func selectingZeroWindowAccountSticks() {
        let charted = Self.state(label: "Codex Plus",
                                 snapshot: Self.snapshot(windows: [Self.weekly]))
        let business = Self.state(label: "Codex Business",
                                  snapshot: Self.snapshot(windows: []))
        let states = [charted, business]

        // No window id, exactly what selecting a zero-window account produces.
        let selection = HistorySelection(accountID: business.id, windowID: nil)

        #expect(HistoryView.resolveState(in: states, selection: selection)?.id == business.id)
        #expect(HistoryView.windowContent(for: business, selection: selection)
                == .noLimitWindows)
    }

    @Test("A stale window id falls back to the preferred window, not to no content")
    func staleWindowIDFallsBackToPreferred() {
        let state = Self.state(snapshot: Self.snapshot(windows: [Self.monthly, Self.weekly]))
        let selection = HistorySelection(accountID: state.id, windowID: "weekly:Gone")

        #expect(HistoryView.windowContent(for: state, selection: selection)
                == .window(Self.weekly.id))
    }

    @Test("An explicit window id is honoured over the preferred window")
    func explicitWindowIDWins() {
        let state = Self.state(snapshot: Self.snapshot(windows: [Self.monthly, Self.weekly]))
        let selection = HistorySelection(accountID: state.id, windowID: Self.monthly.id)

        #expect(HistoryView.windowContent(for: state, selection: selection)
                == .window(Self.monthly.id))
    }

    @Test("No accounts still resolves to nothing so the empty state is preserved")
    func noAccountsResolvesNil() {
        #expect(HistoryView.resolveState(in: [], selection: HistorySelection()) == nil)
        #expect(HistoryView.resolveState(
            in: [], selection: HistorySelection(accountID: UUID())) == nil)
    }
}
