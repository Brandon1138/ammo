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

enum SharedStore {
    static var fileURL: URL {
        AppGroup.containerURL.appendingPathComponent("usage-states.json")
    }

    private static var lock: SharedFileLock {
        SharedFileLock(url: AppGroup.containerURL.appendingPathComponent("usage-states.lock"))
    }

    static func load() -> [AccountState] {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let states = try decoder.decode([AccountState].self, from: data)
            AmmoLog.sharedStore.info("Loaded \(states.count, privacy: .public) account states")
            return states
        } catch CocoaError.fileReadNoSuchFile {
            AmmoLog.sharedStore.notice("No shared usage cache exists yet")
            return []
        } catch {
            AmmoLog.sharedStore.error("Unable to load shared usage cache: \(String(describing: error), privacy: .private)")
            return []
        }
    }

    static func insert(_ state: AccountState) throws {
        try mutate { states in
            states.append(state)
        }
    }

    static func remove(id: UUID) throws {
        try mutate { states in
            states.removeAll { $0.account.id == id }
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
        var transition: SnapshotTransition?
        try mutate { states in
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
        do {
            try UsageHistoryStore.record(snapshot: snapshot, for: id)
        } catch {
            AmmoLog.sharedStore.error("Unable to record usage history: \(String(describing: error), privacy: .private)")
        }
        return transition
    }

    static func record(failure: UsageFailureKind, for id: UUID) throws {
        try mutate { states in
            guard let index = states.firstIndex(where: { $0.account.id == id }) else { return }
            states[index].lastError = nil
            states[index].lastFailure = failure
        }
    }

    private static func mutate(_ body: (inout [AccountState]) -> Void) throws {
        try lock.withLock {
            var states = loadUnlocked()
            body(&states)
            try saveUnlocked(states)
        }
    }

    private static func loadUnlocked() -> [AccountState] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AccountState].self, from: data)) ?? []
    }

    private static func saveUnlocked(_ states: [AccountState]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(states)
        try data.write(to: fileURL, options: .atomic)
        AmmoLog.sharedStore.info("Saved \(states.count, privacy: .public) account states")
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
