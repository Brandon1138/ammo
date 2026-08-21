import Foundation
import Security
import Testing
import UsageKit

@testable import Ammo

/// MIK-156 — an account's identity must survive an expired provider session.
///
/// History, the refresh ledger and every Lock Screen widget binding are keyed by
/// `StoredAccount.id`. These tests hold that key fixed across a credential
/// replacement, and check the natural key that lets a fresh login find its way
/// back to the entry it belongs to.
@Suite("Account identity and re-authentication", .serialized)
struct MIK156Tests {

    // MARK: - Fixtures

    private static let codexSubject = "acct_11112222-3333-4444-5555-666677778888"

    private static func codexIdentity(
        subject: String = codexSubject
    ) -> AccountIdentity {
        AccountIdentity(provider: .codex, subject: subject)
    }

    private static func codexTokens(
        accessToken: String,
        subject: String = codexSubject
    ) -> OAuthTokens {
        OAuthTokens(accessToken: accessToken,
                    refreshToken: "refresh-for-\(accessToken)",
                    accountID: subject)
    }

    /// Inserts a live account with credentials and one history sample, then
    /// tears every durable artifact back down.
    private func withLiveAccount(
        _ account: StoredAccount,
        tokens: OAuthTokens,
        body: (StoredAccount) throws -> Void
    ) throws {
        try SharedStore.insert(AccountState(account: account))
        defer {
            KeychainStore.delete(for: account.id)
            RefreshLedgerStore.remove(accountID: account.id)
            try? UsageHistoryStore.remove(accountID: account.id)
            try? SharedStore.remove(id: account.id)
        }
        try KeychainStore.save(tokens, for: account.id)
        try UsageHistoryStore.record(snapshot: Self.snapshot(at: Date(timeIntervalSince1970: 1_700_000_000)),
                                     for: account.id)
        try body(account)
    }

    private static func snapshot(at date: Date) -> UsageSnapshot {
        UsageSnapshot(provider: .codex,
                      plan: "pro",
                      windows: [LimitWindow(kind: .weekly,
                                            label: "Weekly",
                                            usedPercent: 42,
                                            resetsAt: date.addingTimeInterval(86_400))],
                      fetchedAt: date)
    }

    /// Counts Keychain items stored under this account's key, across every
    /// access group the app can reach. Re-authentication must overwrite, so this
    /// stays at one.
    private static func keychainItemCount(for id: UUID) -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainStore.service,
            kSecAttrAccount as String: id.uuidString,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]]
        else { return 0 }
        return items.count
    }

    // MARK: - Dedupe on add

    @Test("A fresh login matching a stored natural key lands on that account")
    func matchingIdentitySelectsTheExistingAccount() {
        let existing = StoredAccount(provider: .codex,
                                     label: "Work",
                                     identity: Self.codexIdentity())
        let other = StoredAccount(provider: .cursor,
                                  label: "Cursor",
                                  identity: AccountIdentity(provider: .cursor,
                                                            subject: "user_01ABC"))
        let states = [AccountState(account: other), AccountState(account: existing)]

        let matched = AccountReconnection.existingAccount(
            matching: AccountIdentityResolver.identity(
                provider: .codex,
                tokens: Self.codexTokens(accessToken: "brand-new-token")),
            in: states)

        #expect(matched?.id == existing.id)
    }

    @Test("A different provider account is a different account, so it is added")
    func differentSubjectIsNotAMatch() {
        let states = [AccountState(account: StoredAccount(provider: .codex,
                                                          label: "Work",
                                                          identity: Self.codexIdentity()))]

        let matched = AccountReconnection.existingAccount(
            matching: Self.codexIdentity(subject: "acct_someone-else"),
            in: states)

        #expect(matched == nil)
    }

    @Test("The same opaque subject at another provider never claims this account")
    func identityMatchIsScopedToItsProvider() {
        let states = [AccountState(account: StoredAccount(provider: .codex,
                                                          label: "Work",
                                                          identity: Self.codexIdentity()))]

        let matched = AccountReconnection.existingAccount(
            matching: AccountIdentity(provider: .cursor, subject: Self.codexSubject),
            in: states)

        #expect(matched == nil)
    }

    // MARK: - No-identity fallback

    @Test("A provider that exposes no identity keeps today's behavior")
    func credentialWithoutIdentityNeverDedupes() {
        // Claude's token exchange returns tokens only. Nothing may be matched on,
        // so the add flow mints a fresh id exactly as it does today.
        let claudeTokens = OAuthTokens(accessToken: "sk-ant-oat01-abc",
                                       refreshToken: "sk-ant-ort01-def")
        let identity = AccountIdentityResolver.identity(provider: .claude, tokens: claudeTokens)
        let states = [AccountState(account: StoredAccount(provider: .claude, label: "Claude"))]

        #expect(identity == nil)
        #expect(AccountReconnection.existingAccount(matching: identity, in: states) == nil)
    }

    @Test("An account stored without a natural key is never claimed by a login")
    func accountWithoutStoredIdentityIsNeverClaimed() {
        // Entries persisted before natural keys existed decode with none. An
        // unknown key is unknown, not "the same as this other unknown one".
        let legacy = StoredAccount(provider: .codex, label: "Legacy", identity: nil)

        #expect(AccountReconnection.existingAccount(matching: Self.codexIdentity(),
                                                    in: [AccountState(account: legacy)]) == nil)
    }

    @Test("A no-identity provider can still be repaired in place")
    func reauthenticationIsAllowedWithoutANaturalKey() throws {
        // Neither side has a key to compare, so the explicit "sign in again"
        // action is trusted rather than blocked.
        #expect(throws: Never.self) {
            try AccountReconnection.requireSameAccount(existing: nil,
                                                       incoming: nil,
                                                       provider: .claude)
        }
        #expect(throws: Never.self) {
            try AccountReconnection.requireSameAccount(existing: nil,
                                                       incoming: Self.codexIdentity(),
                                                       provider: .codex)
        }
    }

    @Test("A sign-in for a different provider account is refused, not written")
    func identityMismatchIsRefused() {
        #expect(throws: AccountReconnection.IdentityMismatchError.self) {
            try AccountReconnection.requireSameAccount(
                existing: Self.codexIdentity(),
                incoming: Self.codexIdentity(subject: "acct_someone-else"),
                provider: .codex)
        }
    }

    // MARK: - Re-authentication in place

    @Test("Re-authenticating replaces the credential under the same account id")
    func reauthenticationPreservesTheAccountID() throws {
        let account = StoredAccount(provider: .codex,
                                    label: "Work",
                                    identity: Self.codexIdentity())
        try withLiveAccount(account, tokens: Self.codexTokens(accessToken: "expired")) { account in
            let updated = try AccountReconnection.apply(
                to: account,
                tokens: Self.codexTokens(accessToken: "fresh"),
                imported: false)

            #expect(updated.id == account.id)
            let states = SharedStore.load().filter { $0.account.provider == .codex }
            #expect(states.filter { $0.id == account.id }.count == 1)

            // The credential itself is the only thing that changed.
            let loaded = try #require(KeychainStore.load(for: account.id))
            #expect(loaded.accessToken == "fresh")
            #expect(loaded.refreshToken == "refresh-for-fresh")
        }
    }

    @Test("History stays attached because its key never moved")
    func historySurvivesReauthentication() throws {
        let account = StoredAccount(provider: .codex,
                                    label: "Work",
                                    identity: Self.codexIdentity())
        try withLiveAccount(account, tokens: Self.codexTokens(accessToken: "expired")) { account in
            let before = UsageHistoryStore.load().filter { $0.accountID == account.id }
            #expect(!before.isEmpty)

            try AccountReconnection.apply(to: account,
                                          tokens: Self.codexTokens(accessToken: "fresh"),
                                          imported: false)

            #expect(UsageHistoryStore.load().filter { $0.accountID == account.id } == before)
        }
    }

    @Test("A widget bound to this account still resolves after re-authentication")
    func widgetBindingSurvivesReauthentication() throws {
        let account = StoredAccount(provider: .codex,
                                    label: "Work",
                                    identity: Self.codexIdentity())
        try withLiveAccount(account, tokens: Self.codexTokens(accessToken: "expired")) { account in
            // What a Lock Screen gauge persists in its SelectAccountIntent.
            let widgetSelection = account.id

            try AccountReconnection.apply(to: account,
                                          tokens: Self.codexTokens(accessToken: "fresh"),
                                          imported: false)

            // AccountQuery.resolve looks the stored identifier up in exactly this
            // cache; a miss is what leaves a gauge frozen on "Account removed".
            let bound = SharedStore.load().first { $0.account.id == widgetSelection }
            #expect(bound?.account.label == "Work")
        }
    }

    @Test("Overwriting the credential leaves exactly one Keychain item behind")
    func reauthenticationLeavesNoOrphanedKeychainItem() throws {
        let account = StoredAccount(provider: .codex,
                                    label: "Work",
                                    identity: Self.codexIdentity())
        try withLiveAccount(account, tokens: Self.codexTokens(accessToken: "expired")) { account in
            #expect(Self.keychainItemCount(for: account.id) == 1)

            try AccountReconnection.apply(to: account,
                                          tokens: Self.codexTokens(accessToken: "fresh"),
                                          imported: false)

            #expect(Self.keychainItemCount(for: account.id) == 1)
        }
    }

    @Test("Fields the re-authentication does not set survive it untouched")
    func unrelatedAccountFieldsArePreserved() throws {
        // The update mutates the persisted value in place rather than replacing
        // it, so metadata owned elsewhere — ordering among it — is carried
        // through opaquely. A blank label likewise never renames the account.
        let account = StoredAccount(provider: .codex,
                                    label: "Work",
                                    tokensImported: true,
                                    identity: Self.codexIdentity())
        try withLiveAccount(account, tokens: Self.codexTokens(accessToken: "expired")) { account in
            let updated = try AccountReconnection.apply(
                to: account,
                tokens: Self.codexTokens(accessToken: "fresh"),
                imported: false,
                label: "   ")

            #expect(updated.label == "Work")
            #expect(updated.provider == .codex)
            #expect(updated.identity == Self.codexIdentity())
            // On-device sign-in supersedes the imported-token restriction.
            #expect(!updated.tokensImported)
        }
    }

    @Test("An account signed in again adopts the natural key it previously lacked")
    func reauthenticationBackfillsAMissingIdentity() throws {
        let account = StoredAccount(provider: .codex, label: "Legacy", identity: nil)
        try withLiveAccount(account, tokens: Self.codexTokens(accessToken: "expired")) { account in
            let updated = try AccountReconnection.apply(
                to: account,
                tokens: Self.codexTokens(accessToken: "fresh"),
                imported: false)

            #expect(updated.id == account.id)
            #expect(updated.identity == Self.codexIdentity())
        }
    }

    @Test("A stored account without a natural key still decodes")
    func legacyAccountDecodesWithoutIdentity() throws {
        let legacy = Data("""
        {"id":"11111111-1111-1111-1111-111111111111","provider":"codex",\
        "label":"Legacy","tokensImported":false}
        """.utf8)

        let decoded = try UsageCacheCodec.decode(StoredAccount.self, from: legacy)

        #expect(decoded.identity == nil)
        #expect(decoded.label == "Legacy")
    }
}
