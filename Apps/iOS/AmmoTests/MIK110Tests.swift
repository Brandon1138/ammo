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

    @Test("Foreground cache hit relies on the activation republish")
    func foregroundCacheHitDoesNotReloadAgain() {
        let outcomes: [RefreshOutcome] = [
            .cached(accountID: accountID, nextEligibleAt: .distantFuture),
        ]

        #expect(!WidgetReloadPolicy.shouldReload(
            after: outcomes,
            reason: .foreground,
            hasCachedSnapshot: true))
    }

    @Test("An account-add cache hit still reloads when a snapshot exists")
    func accountAddedCacheHitReloads() {
        let outcomes: [RefreshOutcome] = [
            .cached(accountID: accountID, nextEligibleAt: .distantFuture),
        ]

        #expect(WidgetReloadPolicy.shouldReload(
            after: outcomes,
            reason: .accountAdded,
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

    @Test("Persisted refresh outcomes rely on the SharedStore write seam")
    func persistedOutcomesDoNotReloadFromCaller() {
        #expect(!WidgetReloadPolicy.shouldReload(
            after: [.refreshed(accountID: accountID)],
            reason: .background,
            hasCachedSnapshot: true))
        #expect(!WidgetReloadPolicy.shouldReload(
            after: [.failed(accountID: accountID,
                            message: "network",
                            nextEligibleAt: nil,
                            didPersist: true)],
            reason: .manual,
            hasCachedSnapshot: false))
    }

    @Test("A cached manual run republishes when accompanying failures wrote nothing")
    func cacheAndUnpersistedFailureReloadFromCaller() {
        #expect(WidgetReloadPolicy.shouldReload(
            after: [
                .cached(accountID: accountID, nextEligibleAt: .distantFuture),
                .failed(accountID: UUID(), message: "cancelled",
                        nextEligibleAt: nil, didPersist: false),
            ],
            reason: .manual,
            hasCachedSnapshot: true))
    }

    @Test("Removal cleanup after the shared-cache commit does not reload twice")
    func removalProgressControlsFallbackReload() {
        struct LaterCleanupFailure: Error {}

        #expect(!AccountMutationStore.needsCallerInvalidation(after:
            AccountMutationStore.RemovalError(
                sharedCacheRemoved: true,
                underlying: LaterCleanupFailure())))
        #expect(AccountMutationStore.needsCallerInvalidation(after:
            AccountMutationStore.RemovalError(
                sharedCacheRemoved: false,
                underlying: LaterCleanupFailure())))
    }

    @Test("A mixed persisted and cached run still relies on the write seam")
    func mixedOutcomesDoNotReloadFromCaller() {
        #expect(!WidgetReloadPolicy.shouldReload(
            after: [
                .refreshed(accountID: accountID),
                .cached(accountID: UUID(), nextEligibleAt: .distantFuture),
            ],
            reason: .foreground,
            hasCachedSnapshot: true))
    }

    // MARK: - Invalidation dispatch

    @Test("Account insertion dispatches exactly once at the write seam")
    func accountInsertionDispatchesOnce() throws {
        let recorder = ReloadRecorder()
        let scheduled = TrailingWorkRecorder()
        let token = WidgetInvalidator.shared.installDispatchOverride(
            { recorder.record($0) },
            schedulingOverride: { scheduled.record($0) })
        defer { _ = token }

        let account = StoredAccount(provider: .claude, label: "Reload probe")
        try SharedStore.insert(AccountState(account: account))
        defer { try? SharedStore.remove(id: account.id) }

        #expect(recorder.reasons == [.accountAdded])
        #expect(scheduled.count == 0)
    }

    @Test("Successful account removal dispatches exactly once at the write seam")
    @MainActor
    func successfulAccountRemovalDispatchesOnce() throws {
        let account = StoredAccount(provider: .claude, label: "Removal reload probe")
        try SharedStore.insert(AccountState(account: account))

        let recorder = ReloadRecorder()
        let scheduled = TrailingWorkRecorder()
        let token = WidgetInvalidator.shared.installDispatchOverride(
            { recorder.record($0) },
            schedulingOverride: { scheduled.record($0) })
        defer { _ = token }

        AccountStore.shared.remove(account)

        #expect(recorder.reasons == [.accountRemoved])
        #expect(scheduled.count == 0)
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

    @Test("A persisted refresh dispatches exactly once without a trailing reload")
    func persistedRefreshDispatchesOnce() {
        let recorder = ReloadRecorder()
        let scheduled = TrailingWorkRecorder()
        let token = WidgetInvalidator.shared.installDispatchOverride(
            { recorder.record($0) },
            schedulingOverride: { scheduled.record($0) })
        defer { _ = token }

        WidgetInvalidator.shared.invalidate(reason: .cacheCommitted)
        if WidgetReloadPolicy.shouldReload(
            after: [.refreshed(accountID: accountID)],
            reason: .foreground,
            hasCachedSnapshot: true
        ) {
            WidgetInvalidator.shared.invalidate(reason: .refreshFinished)
        }

        #expect(recorder.reasons == [.cacheCommitted])
        #expect(scheduled.count == 0)
    }

    @Test("A cache-only manual refresh dispatches exactly once from the caller")
    func cacheOnlyManualRefreshDispatchesOnce() {
        let recorder = ReloadRecorder()
        let scheduled = TrailingWorkRecorder()
        let token = WidgetInvalidator.shared.installDispatchOverride(
            { recorder.record($0) },
            schedulingOverride: { scheduled.record($0) })
        defer { _ = token }

        if WidgetReloadPolicy.shouldReload(
            after: [.cached(accountID: accountID, nextEligibleAt: .distantFuture)],
            reason: .manual,
            hasCachedSnapshot: true
        ) {
            WidgetInvalidator.shared.invalidate(reason: .refreshFinished)
        }

        #expect(recorder.reasons == [.refreshFinished])
        #expect(scheduled.count == 0)
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

    @Test("Foreground activation dispatches once for an unchanged revision")
    @MainActor
    func foregroundUnchangedRevisionDispatchesOnce() {
        let recorder = ReloadRecorder()
        let scheduled = TrailingWorkRecorder()
        let token = WidgetInvalidator.shared.installDispatchOverride(
            { recorder.record($0) },
            schedulingOverride: { scheduled.record($0) })
        defer { _ = token }

        AccountStore.shared.invalidateWidgetsFromCache()
        if WidgetReloadPolicy.shouldReload(
            after: [.cached(accountID: accountID, nextEligibleAt: .distantFuture)],
            reason: .foreground,
            hasCachedSnapshot: true
        ) {
            WidgetInvalidator.shared.invalidate(
                reason: .refreshFinished,
                revision: SharedStoreRevisionStore.load())
        }

        #expect(recorder.reasons == [.appForeground])
        #expect(scheduled.count == 0)
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

    @Test("A failed marker publication invalidates it without resetting the sequence")
    func failedRevisionPublicationPreservesSequence() throws {
        struct PublicationFailure: Error {}

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MIK110-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let revisionURL = directory.appendingPathComponent("usage-states-revision.json")
        let sequenceURL = directory.appendingPathComponent("usage-states-revision-sequence.json")
        let previous = SharedStoreRevision(
            revision: 7,
            writtenAt: Date(timeIntervalSince1970: 1_800_000_000),
            accountCount: 1,
            snapshotCount: 0,
            newestSnapshotAt: nil)
        try UsageCacheCodec.encode(previous).write(to: revisionURL, options: .atomic)

        let published = SharedStoreRevisionStore.record(
            states: [],
            at: Date(timeIntervalSince1970: 1_800_000_001),
            fileURL: revisionURL,
            sequenceFileURL: sequenceURL,
            writeMarker: { _, _ in throw PublicationFailure() })

        #expect(published == nil)
        #expect(SharedStoreRevisionStore.load(from: revisionURL) == nil)
        #expect(!FileManager.default.fileExists(atPath: revisionURL.path))

        let recovered = try #require(SharedStoreRevisionStore.record(
            states: [],
            at: Date(timeIntervalSince1970: 1_800_000_002),
            fileURL: revisionURL,
            sequenceFileURL: sequenceURL))
        #expect(recovered.revision == 9)
    }

    @Test("Cache-write preparation invalidates the marker after preserving its sequence")
    func cacheWritePreparationClosesTerminationGap() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MIK110-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let revisionURL = directory.appendingPathComponent("usage-states-revision.json")
        let sequenceURL = directory.appendingPathComponent("usage-states-revision-sequence.json")
        let previous = SharedStoreRevision(
            revision: 7,
            writtenAt: Date(timeIntervalSince1970: 1_800_000_000),
            accountCount: 1,
            snapshotCount: 0,
            newestSnapshotAt: nil)
        try UsageCacheCodec.encode(previous).write(to: revisionURL, options: .atomic)

        try SharedStoreRevisionStore.prepareForCacheWrite(
            fileURL: revisionURL,
            sequenceFileURL: sequenceURL)

        #expect(SharedStoreRevisionStore.load(from: revisionURL) == nil)
        let recovered = try #require(SharedStoreRevisionStore.record(
            states: [],
            at: Date(timeIntervalSince1970: 1_800_000_001),
            fileURL: revisionURL,
            sequenceFileURL: sequenceURL))
        #expect(recovered.revision == 8)
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

    @Test("A cache read during the cache/revision write gap omits the revision")
    func contendedWriteGapKeepsCacheButOmitsRevision() throws {
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
        let revision = SharedStoreRevision(
            revision: 7,
            writtenAt: Date(timeIntervalSince1970: 1_800_000_000),
            accountCount: oldStates.count,
            snapshotCount: 0,
            newestSnapshotAt: nil)
        try UsageCacheCodec.encode(oldStates).write(to: cacheURL, options: .atomic)
        try UsageCacheCodec.encode(revision).write(to: revisionURL, options: .atomic)

        let lockHeld = DispatchSemaphore(value: 0)
        let releaseLock = DispatchSemaphore(value: 0)
        let holderFinished = DispatchSemaphore(value: 0)
        let holderOutcome = OutcomeBox<Void>()
        DispatchQueue.global().async {
            defer { holderFinished.signal() }
            holderOutcome.store(Result {
                try lock.withLock(timeout: 2) {
                    try UsageCacheCodec.encode(newStates).write(to: cacheURL, options: .atomic)
                    lockHeld.signal()
                    _ = releaseLock.wait(timeout: .now() + 5)
                }
            })
        }
        #expect(lockHeld.wait(timeout: .now() + 2) == .success)
        defer {
            releaseLock.signal()
            _ = holderFinished.wait(timeout: .now() + 2)
        }

        let diskSnapshot = try SharedStore.readCacheSnapshot(
            fileURL: cacheURL,
            revisionURL: revisionURL,
            lock: lock)
        let decoded = try UsageCacheCodec.decode(
            [AccountState].self,
            from: diskSnapshot.data)

        #expect(decoded.map(\.account.label) == ["Old", "New"])
        #expect(diskSnapshot.revision == nil)

        releaseLock.signal()
        #expect(holderFinished.wait(timeout: .now() + 2) == .success)
        try holderOutcome.take()?.get()
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
        #expect(SharedStore.authoritativeAccountIDs(
            states,
            deletedIDs: nil) == nil)
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
