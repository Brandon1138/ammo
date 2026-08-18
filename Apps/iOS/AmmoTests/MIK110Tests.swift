import Foundation
import Testing
import UsageKit

@testable import Ammo

/// Serialized: the reload policy is pure, but the invalidator is a process-wide
/// singleton with a coalescing window and the shared store is a real file in the
/// App Group container. Parallel cases would race both.
@Suite("MIK-110 widget first load / MIK-51 stale after foreground", .serialized)
struct MIK110Tests {
    private let accountID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

    // MARK: - Reload policy

    @Test("Foreground cache hit reloads a placeholder widget")
    func foregroundCacheHitReloads() {
        let outcomes: [RefreshOutcome] = [
            .cached(accountID: accountID, nextEligibleAt: .distantFuture),
        ]

        #expect(WidgetReloadPolicy.shouldReload(
            after: outcomes,
            reason: .foreground,
            hasCachedSnapshot: true))
    }

    @Test("A throttled pull-to-refresh still brings widgets in line with the app")
    func throttledManualRefreshReloads() {
        let outcomes: [RefreshOutcome] = [
            .cached(accountID: accountID, nextEligibleAt: .distantFuture),
        ]

        #expect(WidgetReloadPolicy.shouldReload(
            after: outcomes,
            reason: .manual,
            hasCachedSnapshot: true))
    }

    @Test("Passive cache hit does not spend widget reload budget")
    func backgroundCacheHitDoesNotReload() {
        let outcomes: [RefreshOutcome] = [
            .cached(accountID: accountID, nextEligibleAt: .distantFuture),
        ]

        #expect(!WidgetReloadPolicy.shouldReload(
            after: outcomes,
            reason: .background,
            hasCachedSnapshot: true))
    }

    @Test("A user-initiated refresh with nothing cached has nothing to publish")
    func userInitiatedWithoutCacheDoesNotReload() {
        let outcomes: [RefreshOutcome] = [
            .cached(accountID: accountID, nextEligibleAt: .distantFuture),
        ]

        #expect(!WidgetReloadPolicy.shouldReload(
            after: outcomes,
            reason: .foreground,
            hasCachedSnapshot: false))
    }

    @Test("Fresh snapshots and visible failures always reload")
    func mutationsReload() {
        #expect(WidgetReloadPolicy.shouldReload(
            after: [.refreshed(accountID: accountID)],
            reason: .background,
            hasCachedSnapshot: true))
        #expect(WidgetReloadPolicy.shouldReload(
            after: [.failed(accountID: accountID,
                            message: "network",
                            nextEligibleAt: nil)],
            reason: .manual,
            hasCachedSnapshot: false))
    }

    // MARK: - Invalidation dispatch

    @Test("A cache commit dispatches a widget reload")
    func commitDispatchesReload() throws {
        let recorder = ReloadRecorder()
        let token = WidgetInvalidator.shared.installDispatchOverride { recorder.record($0) }
        defer { _ = token }

        let account = StoredAccount(provider: .claude, label: "Reload probe")
        try SharedStore.insert(AccountState(account: account))
        defer { try? SharedStore.remove(id: account.id) }

        #expect(recorder.reasons.contains(.accountAdded))
    }

    @Test("A burst of per-account commits collapses into one reload request")
    func burstIsCoalesced() throws {
        let recorder = ReloadRecorder()
        let token = WidgetInvalidator.shared.installDispatchOverride { recorder.record($0) }
        defer { _ = token }

        for _ in 0..<8 {
            WidgetInvalidator.shared.invalidate(reason: .cacheCommitted)
        }

        // Leading dispatch only; the trailing one fires after the window and is
        // deliberately not awaited here — what matters is that eight commits do
        // not become eight reload requests.
        #expect(recorder.count == 1)
    }

    @Test("Requests spaced beyond the coalescing window each dispatch")
    func spacedRequestsBothDispatch() {
        let recorder = ReloadRecorder()
        let token = WidgetInvalidator.shared.installDispatchOverride { recorder.record($0) }
        defer { _ = token }

        let start = Date()
        WidgetInvalidator.shared.invalidate(reason: .appForeground, now: start)
        WidgetInvalidator.shared.invalidate(
            reason: .refreshFinished,
            now: start.addingTimeInterval(WidgetInvalidator.coalescingWindow + 1))

        #expect(recorder.count == 2)
        #expect(recorder.reasons == [.appForeground, .refreshFinished])
    }

    @Test("Opening the app publishes the cache without waiting for the network")
    @MainActor
    func foregroundPublishesCacheImmediately() {
        let recorder = ReloadRecorder()
        let token = WidgetInvalidator.shared.installDispatchOverride { recorder.record($0) }
        defer { _ = token }

        AccountStore.shared.invalidateWidgetsFromCache()

        #expect(recorder.reasons == [.appForeground])
    }

    // MARK: - Canonical snapshot persistence

    @Test("A committed snapshot is what the shared store hands back to a timeline")
    func committedSnapshotIsReadable() throws {
        let account = StoredAccount(provider: .codex, label: "Canonical probe")
        try SharedStore.insert(AccountState(account: account))
        defer { try? SharedStore.remove(id: account.id) }

        // Whole seconds: the shared cache is ISO-8601, which has no room for the
        // sub-second component `Date()` would carry in.
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = UsageSnapshot(
            provider: .codex,
            plan: "plus",
            windows: [
                LimitWindow(kind: .weekly, label: "Weekly", usedPercent: 41,
                            resetsAt: fetchedAt.addingTimeInterval(4 * 86_400)),
            ],
            fetchedAt: fetchedAt)
        try SharedStore.commit(snapshot: snapshot, for: account.id)

        let reloaded = SharedStore.load().first { $0.id == account.id }
        #expect(reloaded?.snapshot?.windows.first?.usedPercent == 41)
        #expect(reloaded?.updatedAt == fetchedAt)
    }

    @Test("Every committed write publishes a newer revision describing it")
    func writesPublishRevisions() throws {
        let before = SharedStoreRevisionStore.load()?.revision ?? 0

        let account = StoredAccount(provider: .cursor, label: "Revision probe")
        try SharedStore.insert(AccountState(account: account))
        defer { try? SharedStore.remove(id: account.id) }

        let afterInsert = try #require(SharedStoreRevisionStore.load())
        #expect(afterInsert.revision > before)
        #expect(afterInsert.accountCount >= 1)

        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_123)
        try SharedStore.commit(
            snapshot: UsageSnapshot(provider: .cursor, plan: nil, windows: [],
                                    fetchedAt: fetchedAt),
            for: account.id)

        let afterCommit = try #require(SharedStoreRevisionStore.load())
        #expect(afterCommit.revision > afterInsert.revision)
        #expect(afterCommit.snapshotCount >= 1)
        #expect(afterCommit.newestSnapshotAt == fetchedAt)
    }

    // MARK: - Tombstone filtering on the read path

    @Test("Unreadable tombstones render the cache instead of blanking every widget")
    func unknownTombstonesKeepCachedStates() {
        let states = [
            AccountState(account: StoredAccount(provider: .claude, label: "Claude")),
            AccountState(account: StoredAccount(provider: .codex, label: "Codex")),
        ]

        #expect(SharedStore.removingDeleted(states, deletedIDs: nil).count == 2)
    }

    @Test("A readable tombstone still removes the account it names")
    func knownTombstoneFilters() {
        let deleted = AccountState(account: StoredAccount(provider: .claude, label: "Claude"))
        let kept = AccountState(account: StoredAccount(provider: .codex, label: "Codex"))

        let remaining = SharedStore.removingDeleted([deleted, kept],
                                                    deletedIDs: [deleted.id])

        #expect(remaining.map(\.id) == [kept.id])
    }

    @Test("An empty tombstone set removes nothing")
    func emptyTombstoneSetKeepsEverything() {
        let states = [
            AccountState(account: StoredAccount(provider: .openRouter, label: "OpenRouter")),
        ]

        #expect(SharedStore.removingDeleted(states, deletedIDs: []).count == 1)
    }
}

/// Collects reload requests dispatched through `WidgetInvalidator`.
private final class ReloadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [WidgetInvalidationReason] = []

    func record(_ reason: WidgetInvalidationReason) {
        lock.lock()
        recorded.append(reason)
        lock.unlock()
    }

    var reasons: [WidgetInvalidationReason] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var count: Int { reasons.count }
}
