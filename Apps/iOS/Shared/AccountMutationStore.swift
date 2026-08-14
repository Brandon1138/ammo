import Foundation

/// Durable cross-store account transaction journal.
///
/// Tokens cannot share an atomic transaction with App Group files. Recording
/// intent first makes crashes and partial failures recoverable on next launch.
enum AccountMutationStore {
    enum Kind: String, Codable, Sendable {
        case adding
        case removing
    }

    struct Mutation: Codable, Sendable {
        let kind: Kind
        let account: StoredAccount
    }

    enum RecoveryAction: Equatable {
        case finishCommittedAdd
        case rollBackAdd
        case finishRemoval
    }

    private struct Journal: Codable {
        var mutations: [String: Mutation] = [:]
    }

    private static var fileURL: URL {
        AppGroup.containerURL.appendingPathComponent("account-mutations.json")
    }

    private static var lock: SharedFileLock {
        SharedFileLock(url: AppGroup.containerURL.appendingPathComponent("account-mutations.lock"))
    }

    static func begin(_ kind: Kind, account: StoredAccount) throws {
        try mutate { journal in
            journal.mutations[account.id.uuidString] = Mutation(kind: kind, account: account)
        }
    }

    static func finish(accountID: UUID) throws {
        try mutate { journal in
            journal.mutations.removeValue(forKey: accountID.uuidString)
        }
    }

    static func recoverPending() {
        let pending: [Mutation]
        do {
            pending = try load()
        } catch {
            AmmoLog.sharedStore.error("Unable to read account transaction journal: \(String(describing: error), privacy: .private)")
            return
        }

        for mutation in pending {
            let hasState = SharedStore.load().contains { $0.id == mutation.account.id }
            let hasCredentials = KeychainStore.load(for: mutation.account.id) != nil
            do {
                switch recoveryAction(for: mutation.kind,
                                      hasState: hasState,
                                      hasCredentials: hasCredentials) {
                case .finishCommittedAdd:
                    try finish(accountID: mutation.account.id)
                case .rollBackAdd, .finishRemoval:
                    try cleanUp(account: mutation.account)
                }
            } catch {
                // Leave transaction durable. Next app launch retries idempotent cleanup.
                AmmoLog.sharedStore.error("Unable to recover account transaction: \(String(describing: error), privacy: .private)")
            }
        }
    }

    static func rollBackAdd(_ account: StoredAccount) throws {
        try cleanUp(account: account)
    }

    static func finishRemoval(_ account: StoredAccount) throws {
        try cleanUp(account: account)
    }

    static func recoveryAction(
        for kind: Kind,
        hasState: Bool,
        hasCredentials: Bool
    ) -> RecoveryAction {
        switch kind {
        case .adding where hasState && hasCredentials:
            .finishCommittedAdd
        case .adding:
            .rollBackAdd
        case .removing:
            .finishRemoval
        }
    }

    private static func cleanUp(account: StoredAccount) throws {
        // Tombstone is durable logical commit. Remaining deletes are idempotent
        // cleanup and may safely resume after interruption.
        try AccountDeletionStore.markDeleted(account.id)
        try KeychainStore.deleteOrThrow(for: account.id)
        try RefreshLedgerStore.removeOrThrow(accountID: account.id)
        try SharedStore.remove(id: account.id)
        try UsageHistoryStore.remove(accountID: account.id)
        try finish(accountID: account.id)
    }

    private static func load() throws -> [Mutation] {
        try lock.withLock {
            Array(try loadUnlocked().mutations.values)
        }
    }

    private static func mutate(_ body: (inout Journal) -> Void) throws {
        try lock.withLock(timeout: 5) {
            var journal = try loadUnlocked()
            body(&journal)
            try saveUnlocked(journal)
        }
    }

    private static func loadUnlocked() throws -> Journal {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(Journal.self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return Journal()
        }
    }

    private static func saveUnlocked(_ journal: Journal) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(journal).write(to: fileURL, options: .atomic)
    }
}
