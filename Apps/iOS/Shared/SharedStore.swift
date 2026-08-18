import Foundation
import UsageKit

/// Everything in Shared/ is compiled into both the app and the widget extension.
/// Both processes may refresh usage, so mutations are coordinated with a file
/// lock and committed atomically.

enum AppGroup {
    static let id = "group.com.brandon.ammo"

    static var containerURL: URL {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: id) else {
            // Previews can lack the entitlement, so keep the non-crashing
            // fallback while making the failure visible on a real device.
            AmmoLog.sharedStore.fault("App Group container unavailable; falling back to temporary storage")
            return FileManager.default.temporaryDirectory
        }
        return url
    }
}

/// One configured account. Tokens live in the Keychain, never in this struct.
struct StoredAccount: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var provider: ProviderID
    var label: String
    /// Tokens were pasted from a desktop CLI rather than issued to this device.
    /// Refreshing could rotate the CLI's refresh token and log it out, so
    /// refresh is forbidden for imported accounts.
    var tokensImported: Bool

    init(id: UUID = UUID(), provider: ProviderID, label: String, tokensImported: Bool = false) {
        self.id = id
        self.provider = provider
        self.label = label
        self.tokensImported = tokensImported
    }
}

/// An account plus its latest fetch outcome — the unit the widget renders.
struct AccountState: Codable, Identifiable, Sendable {
    var account: StoredAccount
    var snapshot: UsageSnapshot?
    /// Kept only to migrate raw descriptions persisted by builds before 0.1.0 (12).
    /// New failures are stored exclusively as stable, non-technical categories.
    var lastError: String?
    var lastFailure: UsageFailureKind?
    var updatedAt: Date?

    var id: UUID { account.id }

    var activeFailure: UsageFailureKind? {
        if let lastFailure { return lastFailure }
        return lastError.map(UsageFailureClassifier.classifyLegacyDescription)
    }
}

/// Cache payload and diagnostic revision observed during one locked read.
struct SharedStoreSnapshot: Sendable {
    let states: [AccountState]
    let revision: SharedStoreRevision?
}

/// Raw disk pair used by the production decoder and focused lock tests.
struct SharedStoreDiskSnapshot: Sendable {
    let data: Data
    let revision: SharedStoreRevision?
}

enum SharedStore {
    static var fileURL: URL {
        AppGroup.containerURL.appendingPathComponent("usage-states.json")
    }

    private static var lock: SharedFileLock {
        SharedFileLock(url: AppGroup.containerURL.appendingPathComponent("usage-states.lock"))
    }

    static func load() -> [AccountState] {
        loadSnapshot().states
    }

    /// Reads cache bytes and their revision while holding the writer's lock.
    /// The decoded states may outlive the lock, but both source files always
    /// come from the same committed write.
    static func loadSnapshot() -> SharedStoreSnapshot {
        if DemoModeStore.isEnabled {
            return SharedStoreSnapshot(states: DemoData.states(), revision: nil)
        }
        removeLegacyCodexBillingCache()
        let startedAt = Date()
        do {
            let diskSnapshot = try readCacheSnapshot(
                fileURL: fileURL,
                revisionURL: SharedStoreRevisionStore.fileURL,
                lock: lock)
            let decoded = sanitize(
                try UsageCacheCodec.decode([AccountState].self, from: diskSnapshot.data))
            let states = removingDeleted(decoded)
            AmmoLog.sharedStore.info(
                """
                Loaded \(states.count, privacy: .public) account states \
                (\(diskSnapshot.data.count, privacy: .public) bytes, \
                \(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) ms, \
                \(diskSnapshot.revision?.logDescription ?? "rev=unknown", privacy: .public))
                """)
            return SharedStoreSnapshot(states: states, revision: diskSnapshot.revision)
        } catch CocoaError.fileReadNoSuchFile {
            AmmoLog.sharedStore.notice("No shared usage cache exists yet")
            return SharedStoreSnapshot(states: [], revision: nil)
        } catch {
            AmmoLog.sharedStore.error("Unable to load shared usage cache: \(String(describing: error), privacy: .private)")
            return SharedStoreSnapshot(states: [], revision: nil)
        }
    }

    static func readCacheSnapshot(
        fileURL: URL,
        revisionURL: URL,
        lock: SharedFileLock
    ) throws -> SharedStoreDiskSnapshot {
        do {
            return try lock.withLock {
                SharedStoreDiskSnapshot(
                    data: try Data(contentsOf: fileURL),
                    revision: SharedStoreRevisionStore.load(from: revisionURL))
            }
        } catch let lockError as SharedFileLock.LockError {
            // The cache file itself is atomically replaced, so contention must
            // not blank otherwise usable states. It does mean a writer can be
            // between replacing the cache and publishing the matching revision,
            // though, and two equal lock-free revision reads cannot detect that
            // gap. Preserve the bytes but make no diagnostic revision claim.
            AmmoLog.sharedStore.notice(
                "Cache lock unavailable (\(String(describing: lockError), privacy: .public)); rendering atomic cache with unknown revision")
            return SharedStoreDiskSnapshot(
                data: try Data(contentsOf: fileURL),
                revision: nil)
        }
    }

    /// Drops tombstoned accounts from a decoded cache.
    ///
    /// When the current tombstone set cannot be read, previously observed
    /// tombstones still filter the cache. Unknown IDs remain visible, preserving
    /// live cached accounts instead of blanking every widget during contention.
    /// Writers keep failing closed via `AccountDeletionStore.isDeleted`, so
    /// nothing is re-persisted for an account whose status is unknown.
    static func removingDeleted(
        _ states: [AccountState],
        deletedIDs: Set<UUID>? = AccountDeletionStore.deletedIDs()
            ?? AccountDeletionStore.deletedIDs(timeout: 1),
        knownDeletedIDs: Set<UUID> = AccountDeletionStore.lastKnownDeletedIDs
    ) -> [AccountState] {
        let effectiveDeletedIDs = knownDeletedIDs.union(deletedIDs ?? [])
        if deletedIDs == nil {
            AmmoLog.sharedStore.notice(
                "Tombstones unreadable; filtering \(effectiveDeletedIDs.count, privacy: .public) known deleted accounts")
        }
        return states.filter { !effectiveDeletedIDs.contains($0.id) }
    }

    static func insert(_ state: AccountState) throws {
        guard !AccountDeletionStore.isDeleted(state.id) else { throw CancellationError() }
        let revision = try mutate { states in
            guard !AccountDeletionStore.isDeleted(state.id) else { return }
            states.append(state)
        }
        WidgetInvalidator.shared.invalidate(reason: .accountAdded, revision: revision)
    }

    static func remove(id: UUID) throws {
        let revision = try mutate { states in
            states.removeAll { $0.account.id == id }
        }
        defer { WidgetInvalidator.shared.invalidate(reason: .accountRemoved, revision: revision) }
        do {
            try RawUsagePayloadStore.remove(accountID: id)
        } catch {
            AmmoLog.sharedStore.error("Unable to remove raw usage payloads: \(String(describing: error), privacy: .private)")
        }
        do {
            try UsageHistoryStore.remove(accountID: id)
        } catch {
            AmmoLog.sharedStore.error("Unable to remove usage history: \(String(describing: error), privacy: .private)")
        }
    }

    /// The single snapshot-acceptance seam. A later notification service should
    /// inspect `previousSnapshot` and `currentSnapshot` here before the new value
    /// replaces the old one, regardless of whether app or widget fetched.
    ///
    /// On-demand notification detection belongs at this seam too: compare stable
    /// `OnDemandUsage.id` values to detect the first paid spend after included
    /// quota is exhausted ("on-demand started"), low remaining balance, exhausted
    /// balance/cap, and provider replenishment or reset. Persist deduplicated
    /// events separately; notification authorization and delivery must not be
    /// coupled to accepting the snapshot.
    @discardableResult
    static func commit(snapshot: UsageSnapshot, for id: UUID) throws -> SnapshotTransition? {
        guard !AccountDeletionStore.isDeleted(id) else { return nil }
        var transition: SnapshotTransition?
        let revision = try mutate { states in
            guard !AccountDeletionStore.isDeleted(id) else { return }
            guard let index = states.firstIndex(where: { $0.account.id == id }) else { return }
            let previous = states[index].snapshot
            states[index].snapshot = snapshot
            states[index].lastError = nil
            states[index].lastFailure = nil
            states[index].updatedAt = snapshot.fetchedAt
            transition = SnapshotTransition(account: states[index].account,
                                            previousSnapshot: previous,
                                            currentSnapshot: snapshot)
        }
        if transition != nil, !AccountDeletionStore.isDeleted(id) {
            do {
                try UsageHistoryStore.record(snapshot: snapshot, for: id)
            } catch {
                AmmoLog.sharedStore.error("Unable to record usage history: \(String(describing: error), privacy: .private)")
            }
        }
        // Invalidation happens here rather than at the caller so no future write
        // path can commit a snapshot and forget to tell WidgetKit, and only once
        // the cache *and* the history the Activity widget reads are both on disk.
        WidgetInvalidator.shared.invalidate(reason: .cacheCommitted, revision: revision)
        return transition
    }

    static func record(failure: UsageFailureKind, for id: UUID) throws {
        guard !AccountDeletionStore.isDeleted(id) else { return }
        let revision = try mutate { states in
            guard !AccountDeletionStore.isDeleted(id) else { return }
            guard let index = states.firstIndex(where: { $0.account.id == id }) else { return }
            states[index].lastError = nil
            states[index].lastFailure = failure
        }
        WidgetInvalidator.shared.invalidate(reason: .cacheCommitted, revision: revision)
    }

    @discardableResult
    private static func mutate(_ body: (inout [AccountState]) -> Void) throws -> SharedStoreRevision? {
        try lock.withLock {
            var states = loadUnlocked()
            body(&states)
            return try saveUnlocked(states)
        }
    }

    private static func loadUnlocked() -> [AccountState] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return sanitize((try? UsageCacheCodec.decode([AccountState].self, from: data)) ?? [])
    }

    /// Commits `states` and publishes the revision describing them. The revision
    /// is written after the cache so a reader that sees revision N can rely on
    /// the bytes for N already being readable.
    private static func saveUnlocked(_ states: [AccountState]) throws -> SharedStoreRevision? {
        let startedAt = Date()
        let data = try UsageCacheCodec.encode(states)
        try data.write(to: fileURL, options: .atomic)
        let revision = SharedStoreRevisionStore.record(states: states)
        AmmoLog.sharedStore.info(
            """
            Saved \(states.count, privacy: .public) account states \
            (\(data.count, privacy: .public) bytes, \
            \(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) ms, \
            \(revision?.logDescription ?? "rev=unwritten", privacy: .public))
            """)
        return revision
    }

    private static func sanitize(_ states: [AccountState]) -> [AccountState] {
        states.map { state in
            var state = state
            state.snapshot = state.snapshot.map {
                CodexProvider.removingUnverifiedBillingData(from: $0)
            }
            return state
        }
    }

    private static func removeLegacyCodexBillingCache() {
        let url = AppGroup.containerURL.appendingPathComponent("codex-billing-balances.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            AmmoLog.sharedStore.notice("Removed legacy Codex web-billing cache")
        } catch {
            AmmoLog.sharedStore.error("Unable to remove legacy Codex web-billing cache")
        }
    }
}

struct SnapshotTransition: Sendable {
    let account: StoredAccount
    let previousSnapshot: UsageSnapshot?
    let currentSnapshot: UsageSnapshot
}

extension UsageSnapshot {
    /// The most-consumed window — what single-gauge surfaces display.
    var worstWindow: LimitWindow? {
        windows.max { $0.usedPercent < $1.usedPercent }
    }
}
