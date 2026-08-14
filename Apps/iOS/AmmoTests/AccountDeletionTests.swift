import Foundation
import Testing
import UsageKit
@testable import Ammo

@Suite("Account deletion persistence", .serialized)
struct AccountDeletionTests {
    @Test("Account transaction recovery never leaves one durable half active")
    func accountTransactionRecoveryActions() {
        #expect(AccountMutationStore.recoveryAction(for: .adding,
                                                    hasState: true,
                                                    hasCredentials: true) == .finishCommittedAdd)
        #expect(AccountMutationStore.recoveryAction(for: .adding,
                                                    hasState: true,
                                                    hasCredentials: false) == .rollBackAdd)
        #expect(AccountMutationStore.recoveryAction(for: .adding,
                                                    hasState: false,
                                                    hasCredentials: true) == .rollBackAdd)
        #expect(AccountMutationStore.recoveryAction(for: .removing,
                                                    hasState: true,
                                                    hasCredentials: true) == .finishRemoval)
    }

    @Test("A tombstone read failure never authorizes credential deletion")
    func tombstoneReadFailureIsUnknown() {
        struct TestError: Error {}

        let status = AccountDeletionStore.status { throw TestError() }

        #expect(status == .unknown)
        #expect(!status.authorizesCredentialDeletion)
        #expect(!status.permitsPersistence)
    }

    @Test("A stale refresh cannot recreate artifacts after account removal")
    func staleRefreshCannotResurrectDeletedAccount() async throws {
        let account = StoredAccount(provider: .claude, label: "Race")
        let snapshot = UsageSnapshot(provider: .claude,
                                     plan: nil,
                                     windows: [],
                                     fetchedAt: Date())
        let gate = PersistenceGate()

        try SharedStore.insert(AccountState(account: account))
        defer {
            KeychainStore.delete(for: account.id)
            RefreshLedgerStore.remove(accountID: account.id)
            try? SharedStore.remove(id: account.id)
        }

        // This task represents provider work that began while the account was
        // still active and resumes only after removal completed.
        let staleRefresh = Task {
            await gate.wait()

            var tokenWriteSucceeded = false
            do {
                try KeychainStore.save(OAuthTokens(accessToken: "stale-token"),
                                       for: account.id)
                tokenWriteSucceeded = true
            } catch {}

            let transition = try? SharedStore.commit(snapshot: snapshot, for: account.id)
            try? UsageHistoryStore.record(snapshot: snapshot, for: account.id)
            RefreshLedgerStore.finishSuccess(accountID: account.id,
                                             snapshot: snapshot,
                                             previousSnapshot: nil)
            return (tokenWriteSucceeded, transition != nil)
        }

        for _ in 0..<100 {
            if await gate.hasWaiter { break }
            await Task.yield()
        }
        try AccountDeletionStore.markDeleted(account.id)
        KeychainStore.delete(for: account.id)
        RefreshLedgerStore.remove(accountID: account.id)
        try SharedStore.remove(id: account.id)
        await gate.open()

        let staleWrites = await staleRefresh.value
        #expect(!staleWrites.0)
        #expect(!staleWrites.1)
        #expect(KeychainStore.load(for: account.id) == nil)
        #expect(!SharedStore.load().contains { $0.id == account.id })
        #expect(!UsageHistoryStore.load().contains { $0.accountID == account.id })
        #expect(!RefreshLedgerStore.claim(accountID: account.id,
                                          reason: .manual).isGranted)
    }
}

private actor PersistenceGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var hasWaiter = false
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        hasWaiter = true
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
