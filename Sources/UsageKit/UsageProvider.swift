import Foundation

/// One adapter per service. Adapters are stateless; credentials are passed per call
/// so a single adapter instance serves any number of accounts.
public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetchUsage(tokens: OAuthTokens) async throws -> UsageSnapshot
    /// Exchanges the refresh token for a fresh token set. May rotate the refresh
    /// token — callers must persist the returned value.
    func refresh(tokens: OAuthTokens) async throws -> OAuthTokens
}
