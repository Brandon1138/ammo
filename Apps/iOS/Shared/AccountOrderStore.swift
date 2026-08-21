import Foundation

/// The person's account ordering, persisted in the App Group so the widget
/// process reads the same list the app writes.
///
/// This is deliberately its own file rather than a field on `StoredAccount`:
/// ordering is a display preference, and keeping it out of the account record
/// means reordering never rewrites the cache that carries account identity and
/// usage snapshots. On-device only — nothing here is synchronized anywhere.
enum AccountOrderStore {
    private struct Payload: Codable {
        var accountIDs: [UUID] = []
    }

    static var fileURL: URL {
        AppGroup.containerURL.appendingPathComponent("account-order.json")
    }

    private static var lock: SharedFileLock {
        SharedFileLock(url: AppGroup.containerURL.appendingPathComponent("account-order.lock"))
    }

    /// The stored order, or an empty order when none has been written yet.
    ///
    /// An unreadable file reads as "no explicit order", which falls back to the
    /// heuristic ordering that shipped before this preference existed. That is
    /// the same board the person saw yesterday, so a transient read failure
    /// degrades instead of blanking anything.
    static func load() -> AccountOrder {
        load(fileURL: fileURL, lock: lock)
    }

    static func load(fileURL: URL, lock: SharedFileLock) -> AccountOrder {
        do {
            return try lock.withLock(timeout: 0.25) {
                try loadUnlocked(fileURL: fileURL)
            }
        } catch {
            // The file is replaced atomically, so a lock-free read yields either
            // the previous or the current complete list. Unrelated contention
            // must not look like "the person never ordered anything".
            if let order = try? loadUnlocked(fileURL: fileURL) {
                return order
            }
            AmmoLog.sharedStore.error(
                "Unable to read account order: \(String(describing: error), privacy: .private)")
            return .empty
        }
    }

    static func save(_ order: AccountOrder) throws {
        try save(order, fileURL: fileURL, lock: lock)
    }

    static func save(_ order: AccountOrder, fileURL: URL, lock: SharedFileLock) throws {
        try lock.withLock {
            try saveUnlocked(order, fileURL: fileURL)
        }
    }

    private static func loadUnlocked(fileURL: URL) throws -> AccountOrder {
        do {
            let payload = try JSONDecoder().decode(Payload.self,
                                                   from: try Data(contentsOf: fileURL))
            return AccountOrder(ids: payload.accountIDs)
        } catch CocoaError.fileReadNoSuchFile {
            return .empty
        }
    }

    private static func saveUnlocked(_ order: AccountOrder, fileURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Payload(accountIDs: order.ids))
        try data.write(to: fileURL, options: .atomic)
    }
}
