import Foundation

/// Persistent account tombstones shared by the app and widget processes.
///
/// Removal marks an ID before deleting any artifacts. A refresh that already
/// crossed a provider boundary therefore still sees the tombstone before its
/// next write, and every persistence store also checks it independently.
enum AccountDeletionStore {
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
            var tombstones = loadUnlocked()
            tombstones.accountIDs.insert(accountID)
            try saveUnlocked(tombstones)
        }
    }

    /// Fails closed: inability to prove an account is active must never let a
    /// stale refresh recreate credentials or cache files after removal.
    static func isDeleted(_ accountID: UUID) -> Bool {
        do {
            return try lock.withLock {
                loadUnlocked().accountIDs.contains(accountID)
            }
        } catch {
            AmmoLog.sharedStore.error("Unable to read account tombstones: \(String(describing: error), privacy: .private)")
            return true
        }
    }

    private static func loadUnlocked() -> Tombstones {
        guard let data = try? Data(contentsOf: fileURL) else { return Tombstones() }
        return (try? JSONDecoder().decode(Tombstones.self, from: data)) ?? Tombstones()
    }

    private static func saveUnlocked(_ tombstones: Tombstones) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(tombstones).write(to: fileURL, options: .atomic)
    }
}
