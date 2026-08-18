import Foundation

/// Persistent account tombstones shared by the app and widget processes.
///
/// Removal marks an ID before deleting any artifacts. A refresh that already
/// crossed a provider boundary therefore still sees the tombstone before its
/// next write, and every persistence store also checks it independently.
enum AccountDeletionStore {
    enum Status: Equatable {
        case active
        case deleted
        case unknown

        /// Only a successfully read tombstone can authorize credential deletion.
        var authorizesCredentialDeletion: Bool { self == .deleted }

        /// File/cache writers still fail closed when deletion state is unknown.
        var permitsPersistence: Bool { self == .active }
    }

    struct StatusUnavailableError: Error {}

    private struct Tombstones: Codable {
        var accountIDs: Set<UUID> = []
    }

    private static var fileURL: URL {
        AppGroup.containerURL.appendingPathComponent("deleted-accounts.json")
    }

    private static var lock: SharedFileLock {
        SharedFileLock(url: AppGroup.containerURL.appendingPathComponent("deleted-accounts.lock"))
    }

    static func markDeleted(_ accountID: UUID) throws {
        try lock.withLock {
            var tombstones = try loadUnlocked()
            tombstones.accountIDs.insert(accountID)
            try saveUnlocked(tombstones)
        }
    }

    static func status(for accountID: UUID, timeout: TimeInterval = 1) -> Status {
        status {
            try lock.withLock(timeout: timeout) {
                try loadUnlocked().accountIDs.contains(accountID)
            }
        }
    }

    /// File/cache persistence fails closed. Credential deletion must instead
    /// inspect `status(for:)` and require a positive `.deleted` result.
    static func isDeleted(_ accountID: UUID) -> Bool {
        !status(for: accountID).permitsPersistence
    }

    /// The whole tombstone set in one lock acquisition, or nil when it could not
    /// be read.
    ///
    /// `isDeleted` is a *writer's* question — it fails closed, so an unreadable
    /// tombstone file answers "deleted" for every account. Asking it once per
    /// account on a read path therefore costs N exclusive locks and can erase an
    /// otherwise healthy cache; the widget process, which only ever reads, paid
    /// both costs. Readers use this instead and decide for themselves what an
    /// unavailable answer means.
    static func deletedIDs(timeout: TimeInterval = 0.25) -> Set<UUID>? {
        do {
            return try lock.withLock(timeout: timeout) {
                try loadUnlocked().accountIDs
            }
        } catch {
            if let lockError = error as? SharedFileLock.LockError,
               lockError.isDataProtectionFailure {
                AmmoLog.sharedStore.notice(
                    "Account tombstones unavailable while protected data is locked")
            } else {
                AmmoLog.sharedStore.error(
                    "Unable to read account tombstones: \(String(describing: error), privacy: .private)")
            }
            return nil
        }
    }

    static func requireActive(_ accountID: UUID, timeout: TimeInterval = 1) throws {
        switch status(for: accountID, timeout: timeout) {
        case .active:
            return
        case .deleted:
            throw CancellationError()
        case .unknown:
            throw StatusUnavailableError()
        }
    }

    /// Separated for deterministic tests of lock/read failures.
    static func status(readTombstone: () throws -> Bool) -> Status {
        do {
            return try readTombstone() ? .deleted : .active
        } catch {
            if let lockError = error as? SharedFileLock.LockError,
               lockError.isDataProtectionFailure {
                AmmoLog.sharedStore.notice("Account tombstones unavailable while protected data is locked")
            } else {
                AmmoLog.sharedStore.error("Unable to read account tombstones: \(String(describing: error), privacy: .private)")
            }
            return .unknown
        }
    }

    private static func loadUnlocked() throws -> Tombstones {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(Tombstones.self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return Tombstones()
        }
    }

    private static func saveUnlocked(_ tombstones: Tombstones) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(tombstones).write(to: fileURL, options: .atomic)
    }
}
