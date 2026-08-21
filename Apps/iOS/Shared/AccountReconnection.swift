import Foundation
import UsageKit

/// Outcome of a completed sign-in that already had somewhere to go.
enum AccountSignInOutcome: Equatable, Sendable {
    /// A new entry was created, with a freshly minted account id.
    case added(UUID)
    /// An existing entry kept its account id and received the new credential.
    case reconnected(UUID)

    var accountID: UUID {
        switch self {
        case .added(let id), .reconnected(let id): id
        }
    }
}

/// Replaces the credential behind an existing account without minting a new id.
///
/// This is the whole point of MIK-156: usage history, the refresh ledger and
/// every Lock Screen widget binding are keyed by `StoredAccount.id`, so an
/// expired provider session must be repaired *under that id*. Nothing here
/// creates or destroys a durable artifact — the Keychain item is overwritten at
/// the same key and the cached entry is edited in place — so unlike add and
/// remove there is no cross-store transaction to journal and no orphan to
/// leave behind if the process dies between the two writes.
enum AccountReconnection {
    /// The new credential belongs to a different provider-side account than the
    /// one being repaired. Overwriting would silently attach one person's
    /// history to another's usage, so the sign-in is refused instead.
    struct IdentityMismatchError: UsageFailureRepresentable, CustomStringConvertible {
        let provider: ProviderID
        var usageFailureKind: UsageFailureKind { .authentication }
        var description: String {
            "That sign-in is for a different \(provider.displayName) account"
        }
    }

    /// - Parameter label: a caller-supplied label. Blank or `nil` keeps the
    ///   label the account already has, so re-authenticating never renames it.
    /// - Returns: the stored account as it now reads.
    @discardableResult
    static func apply(
        to account: StoredAccount,
        tokens: OAuthTokens,
        imported: Bool,
        label: String? = nil
    ) throws -> StoredAccount {
        let identity = AccountIdentityResolver.identity(provider: account.provider,
                                                        tokens: tokens)
        try requireSameAccount(existing: account.identity, incoming: identity,
                               provider: account.provider)

        // Same account id means the same Keychain key: SecItemUpdate replaces
        // the stored token blob in place, leaving no second item behind.
        try KeychainStore.save(tokens, for: account.id)

        var updated = account
        let didUpdate = try SharedStore.updateAccount(id: account.id, clearingFailure: true) { stored in
            stored.tokensImported = imported
            // A provider with no natural key leaves the existing value alone
            // rather than erasing one an earlier credential established.
            if let identity { stored.identity = identity }
            if let label {
                let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { stored.label = trimmed }
            }
            updated = stored
        }
        // The entry disappeared underneath this sign-in (removed on another
        // surface, or tombstoned). Reporting success would leave the person
        // believing a repaired account exists.
        guard didUpdate else { throw CancellationError() }
        AmmoLog.refresh.notice(
            "Replaced credentials in place for \(account.provider.displayName, privacy: .public)")
        return updated
    }

    /// A known key that disagrees is a different person. An absent key on
    /// either side is unknown, not wrong, so it is allowed through — that is
    /// the only way a provider without a natural key can ever be repaired.
    static func requireSameAccount(
        existing: AccountIdentity?,
        incoming: AccountIdentity?,
        provider: ProviderID
    ) throws {
        guard let existing, let incoming, existing != incoming else { return }
        throw IdentityMismatchError(provider: provider)
    }

    /// The dedupe rule for a fresh sign-in through the ordinary add flow.
    ///
    /// Kept pure so the natural-key decision can be exercised without touching
    /// durable stores. An account whose key is unknown never matches, so an
    /// entry from before natural keys existed is left alone rather than being
    /// claimed by the first credential that shows up.
    static func existingAccount(
        matching identity: AccountIdentity?,
        in states: [AccountState]
    ) -> StoredAccount? {
        guard identity != nil else { return nil }
        return states.first {
            AccountIdentityResolver.matches($0.account.identity, identity)
        }?.account
    }
}
