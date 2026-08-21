import CryptoKit
import Foundation

/// The provider-side identity behind one Ammo account, reduced to a digest.
///
/// Ammo's own account id is minted locally and must stay stable forever, because
/// usage history and Lock Screen widget bindings are keyed by it. This natural
/// key is what lets a *later* credential recognize the account it belongs to, so
/// a fresh sign-in can update the existing entry instead of minting a second id.
///
/// The provider subject is hashed rather than stored raw: some providers hand
/// out an email address as the only stable handle, and a digest keeps the store
/// useless to anything that reads it. The digest is device-local — it is written
/// only to the App Group cache and never sent anywhere.
public struct AccountIdentity: Codable, Hashable, Sendable {
    public let provider: ProviderID
    /// Lowercase hex SHA-256 of the domain-separated provider subject.
    public let subjectDigest: String

    public init(provider: ProviderID, subject: String) {
        self.provider = provider
        self.subjectDigest = Self.digest(provider: provider, subject: subject)
    }

    /// Domain-separated so the same opaque string issued by two providers can
    /// never collide into one natural key.
    public static func digest(provider: ProviderID, subject: String) -> String {
        let material = "ammo.account-identity.v1|\(provider.rawValue)|\(subject)"
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Derives the natural key for a credential the app already holds.
///
/// Every value here comes out of material the provider's own auth response
/// already delivered — no extra network call is made to learn who someone is.
/// A provider that exposes no usable subject deliberately yields `nil`: an
/// account with no natural key keeps today's behavior (a fresh id per add)
/// rather than being matched on something unstable like a plan or a label.
public enum AccountIdentityResolver {
    public static func identity(provider: ProviderID, tokens: OAuthTokens) -> AccountIdentity? {
        guard let subject = subject(provider: provider, tokens: tokens) else { return nil }
        return AccountIdentity(provider: provider, subject: subject)
    }

    /// Two identities match only when both exist. An absent key is "unknown",
    /// never "the same as the other unknown one".
    public static func matches(_ lhs: AccountIdentity?, _ rhs: AccountIdentity?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs == rhs
    }

    /// The raw provider subject, before hashing.
    ///
    /// - Codex: `chatgpt_account_id`, already parsed out of the id_token during
    ///   the code exchange and also present in a pasted `~/.codex/auth.json`.
    /// - Cursor: the user id carried in the access-token JWT `sub`, which the
    ///   provider already requires to build its web-session cookie.
    /// - Claude: its token exchange returns tokens only, and the profile call is
    ///   a separate best-effort request, so no key is derived at sign-in.
    /// - OpenRouter: an imported inference key identifies a credential, not a
    ///   person, and no auth response exists to read a subject from.
    static func subject(provider: ProviderID, tokens: OAuthTokens) -> String? {
        let raw: String?
        switch provider {
        case .codex:
            raw = tokens.accountID ?? CodexProvider.chatGPTAccountID(fromJWT: tokens.accessToken)
        case .cursor:
            raw = tokens.accountID ?? CursorProvider.userID(fromJWT: tokens.accessToken)
        case .claude, .openRouter, .antigravity:
            raw = nil
        }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
