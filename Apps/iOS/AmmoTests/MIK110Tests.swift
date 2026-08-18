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

        let start = DispatchTime.now().uptimeNanoseconds
        let spacing = UInt64((WidgetInvalidator.coalescingWindow + 1) * 1_000_000_000)
        WidgetInvalidator.shared.invalidate(reason: .appForeground, nowUptime: start)
        WidgetInvalidator.shared.invalidate(
            reason: .refreshFinished,
            nowUptime: start + spacing)

        #expect(recorder.count == 2)
        #expect(recorder.reasons == [.appForeground, .refreshFinished])
    }

    @Test("An immediate dispatch retires an armed trailing generation")
    func staleTrailingGenerationDoesNotDispatch() {
        let recorder = ReloadRecorder()
        let scheduled = TrailingWorkRecorder()
        let token = WidgetInvalidator.shared.installDispatchOverride(
            { recorder.record($0) },
            schedulingOverride: { scheduled.record($0) })
        defer { _ = token }

        let start = DispatchTime.now().uptimeNanoseconds
        let beyondWindow = UInt64(
            (WidgetInvalidator.coalescingWindow + 1) * 1_000_000_000)
        WidgetInvalidator.shared.invalidate(reason: .appForeground, nowUptime: start)
        WidgetInvalidator.shared.invalidate(reason: .cacheCommitted, nowUptime: start)
        WidgetInvalidator.shared.invalidate(
            reason: .refreshFinished,
            nowUptime: start + beyondWindow)

        #expect(scheduled.count == 1)
        scheduled.runAll()
        #expect(recorder.reasons == [.appForeground, .refreshFinished])
    }

    @Test("A regressed uptime never extends the coalescing delay")
    func regressedUptimeIsClamped() {
        let delay = WidgetInvalidator.coalescingDelay(
            lastDispatchUptime: 10_000_000_000,
            nowUptime: 1_000_000_000)

        #expect(delay == WidgetInvalidator.coalescingWindow)
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

    @Test("An interleaved writer cannot split cache bytes from their revision")
    func interleavedWriteReadsConsistentSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MIK110-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cacheURL = directory.appendingPathComponent("usage-states.json")
        let revisionURL = directory.appendingPathComponent("usage-states-revision.json")
        let lock = SharedFileLock(url: directory.appendingPathComponent("usage-states.lock"))
        let oldStates = [
            AccountState(account: StoredAccount(provider: .claude, label: "Old")),
        ]
        let newStates = oldStates + [
            AccountState(account: StoredAccount(provider: .codex, label: "New")),
        ]
        let oldRevision = SharedStoreRevision(
            revision: 1,
            writtenAt: Date(timeIntervalSince1970: 1_800_000_000),
            accountCount: oldStates.count,
            snapshotCount: 0,
            newestSnapshotAt: nil)
        let newRevision = SharedStoreRevision(
            revision: 2,
            writtenAt: Date(timeIntervalSince1970: 1_800_000_001),
            accountCount: newStates.count,
            snapshotCount: 0,
            newestSnapshotAt: nil)
        try UsageCacheCodec.encode(oldStates).write(to: cacheURL, options: .atomic)
        try UsageCacheCodec.encode(oldRevision).write(to: revisionURL, options: .atomic)

        let cacheWasWritten = DispatchSemaphore(value: 0)
        let allowRevisionWrite = DispatchSemaphore(value: 0)
        let writerFinished = DispatchSemaphore(value: 0)
        let writerOutcome = OutcomeBox<Void>()
        DispatchQueue.global().async {
            defer { writerFinished.signal() }
            writerOutcome.store(Result {
                try lock.withLock(timeout: 2) {
                    try UsageCacheCodec.encode(newStates).write(to: cacheURL, options: .atomic)
                    cacheWasWritten.signal()
                    _ = allowRevisionWrite.wait(timeout: .now() + 2)
                    try UsageCacheCodec.encode(newRevision).write(to: revisionURL, options: .atomic)
                }
            })
        }

        let writerReachedGap = cacheWasWritten.wait(timeout: .now() + 2) == .success
        #expect(writerReachedGap)
        guard writerReachedGap else {
            allowRevisionWrite.signal()
            #expect(writerFinished.wait(timeout: .now() + 2) == .success)
            try writerOutcome.take()?.get()
            return
        }

        let readStarted = DispatchSemaphore(value: 0)
        let readFinished = DispatchSemaphore(value: 0)
        let readerOutcome = OutcomeBox<SharedStoreDiskSnapshot>()
        DispatchQueue.global().async {
            readStarted.signal()
            defer { readFinished.signal() }
            readerOutcome.store(Result {
                try SharedStore.readCacheSnapshot(
                    fileURL: cacheURL,
                    revisionURL: revisionURL,
                    lock: lock)
            })
        }
        #expect(readStarted.wait(timeout: .now() + 2) == .success)
        Thread.sleep(forTimeInterval: 0.1)
        #expect(readFinished.wait(timeout: .now()) == .timedOut)

        allowRevisionWrite.signal()
        #expect(writerFinished.wait(timeout: .now() + 2) == .success)
        try writerOutcome.take()?.get()
        #expect(readFinished.wait(timeout: .now() + 2) == .success)
        let diskSnapshot = try #require(readerOutcome.take()).get()
        let decoded = try UsageCacheCodec.decode(
            [AccountState].self,
            from: diskSnapshot.data)

        #expect(decoded.map(\.account.label) == ["Old", "New"])
        #expect(diskSnapshot.revision == newRevision)
        #expect(diskSnapshot.revision?.accountCount == decoded.count)
    }

    // MARK: - Tombstone filtering on the read path

    @Test("Unreadable tombstones keep cached states with unknown status")
    func unknownTombstonesKeepUnknownCachedStates() {
        let states = [
            AccountState(account: StoredAccount(provider: .claude, label: "Claude")),
            AccountState(account: StoredAccount(provider: .codex, label: "Codex")),
        ]

        #expect(SharedStore.removingDeleted(
            states,
            deletedIDs: nil,
            knownDeletedIDs: []).count == 2)
    }

    @Test("Unreadable tombstones still hide previously observed removals")
    func unknownTombstonesFilterKnownRemovalOnly() {
        let deleted = AccountState(account: StoredAccount(provider: .claude, label: "Claude"))
        let kept = AccountState(account: StoredAccount(provider: .codex, label: "Codex"))

        let remaining = SharedStore.removingDeleted(
            [deleted, kept],
            deletedIDs: nil,
            knownDeletedIDs: [deleted.id])

        #expect(remaining.map(\.id) == [kept.id])
    }

    @Test("A readable tombstone still removes the account it names")
    func knownTombstoneFilters() {
        let deleted = AccountState(account: StoredAccount(provider: .claude, label: "Claude"))
        let kept = AccountState(account: StoredAccount(provider: .codex, label: "Codex"))

        let remaining = SharedStore.removingDeleted([deleted, kept],
                                                    deletedIDs: [deleted.id],
                                                    knownDeletedIDs: [])

        #expect(remaining.map(\.id) == [kept.id])
    }

    @Test("An empty tombstone set removes nothing")
    func emptyTombstoneSetKeepsEverything() {
        let states = [
            AccountState(account: StoredAccount(provider: .openRouter, label: "OpenRouter")),
        ]

        #expect(SharedStore.removingDeleted(
            states,
            deletedIDs: [],
            knownDeletedIDs: []).count == 1)
    }
}

/// Carries a background thread's throwing result back to the test thread.
private final class OutcomeBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: Result<Value, Error>?

    func store(_ result: Result<Value, Error>) {
        lock.lock()
        outcome = result
        lock.unlock()
    }

    func take() -> Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return outcome
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

/// Retains scheduled work so tests can run it after invalidating its generation.
private final class TrailingWorkRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var workItems: [DispatchWorkItem] = []

    func record(_ workItem: DispatchWorkItem) {
        lock.lock()
        workItems.append(workItem)
        lock.unlock()
    }

    func runAll() {
        lock.lock()
        let pending = workItems
        workItems.removeAll()
        lock.unlock()
        pending.forEach { $0.perform() }
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return workItems.count
    }
}
