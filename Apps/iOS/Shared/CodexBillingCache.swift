import Foundation
import UsageKit

/// Sanitized balance data captured from Ammo's separately authenticated
/// ChatGPT billing WKWebView. Browser cookies and access tokens never enter the
/// App Group; only the parsed provider balance does.
struct CodexBillingCacheEntry: Codable, Sendable {
    let accountID: UUID
    let billingAccountID: String
    let usage: OnDemandUsage
    let fetchedAt: Date
}

enum CodexBillingCache {
    private static var fileURL: URL {
        AppGroup.containerURL.appendingPathComponent("codex-billing-balances.json")
    }

    static func entry(for accountID: UUID, billingAccountID: String?) -> CodexBillingCacheEntry? {
        guard let entry = load()[accountID] else { return nil }
        guard billingAccountID == nil || entry.billingAccountID == billingAccountID else {
            return nil
        }
        return entry
    }

    static func save(_ entry: CodexBillingCacheEntry) throws {
        var entries = load()
        entries[entry.accountID] = entry
        try write(entries)
    }

    static func remove(accountID: UUID) {
        var entries = load()
        guard entries.removeValue(forKey: accountID) != nil else { return }
        try? write(entries)
    }

    /// Replaces only the unresolved OAuth credit marker. A provider response that
    /// explicitly disables credits wins over stale web-billing cache data.
    static func enrich(
        _ snapshot: UsageSnapshot,
        accountID: UUID,
        billingAccountID: String?
    ) -> UsageSnapshot {
        guard snapshot.provider == .codex,
              let cached = entry(for: accountID, billingAccountID: billingAccountID)
        else { return snapshot }

        var onDemand = snapshot.onDemand ?? []
        if let index = onDemand.firstIndex(where: { $0.id == cached.usage.id }) {
            guard onDemand[index].isEnabled != false,
                  onDemand[index].remainingAmount == nil
            else { return snapshot }
            onDemand[index] = cached.usage
        } else {
            onDemand.append(cached.usage)
        }
        return UsageSnapshot(
            provider: snapshot.provider,
            plan: snapshot.plan,
            windows: snapshot.windows,
            resetCreditsAvailable: snapshot.resetCreditsAvailable,
            onDemand: onDemand,
            fetchedAt: snapshot.fetchedAt
        )
    }

    private static func load() -> [UUID: CodexBillingCacheEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([UUID: CodexBillingCacheEntry].self, from: data)) ?? [:]
    }

    private static func write(_ entries: [UUID: CodexBillingCacheEntry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(entries).write(to: fileURL, options: .atomic)
    }
}
