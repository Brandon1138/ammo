import Foundation
import Observation
import UsageKit
import WidgetKit

/// Source of truth for accounts and their latest usage. Persists to the App
/// Group (SharedStore) so widgets see every change; tokens go to the Keychain.
@MainActor @Observable
final class AccountStore {
    static let shared = AccountStore()

    private(set) var states: [AccountState]
    private(set) var isRefreshing = false

    private init() {
#if DEBUG
        if Self.usesErrorPreview {
            states = Self.errorPreviewStates
            return
        }
#endif
        states = SharedStore.load()
        for state in states {
            do {
                try KeychainStore.migrateLegacyItemIfNeeded(for: state.account.id)
            } catch {
                AmmoLog.refresh.error("Unable to migrate credentials for \(state.account.provider.displayName, privacy: .public): \(String(describing: error), privacy: .private)")
            }
        }
    }

    // MARK: - Account management

    func add(provider: ProviderID, label: String, tokens: OAuthTokens, imported: Bool) throws {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = StoredAccount(provider: provider,
                                    label: trimmed.isEmpty ? provider.displayName : trimmed,
                                    tokensImported: imported)
        try KeychainStore.save(tokens, for: account.id)
        try SharedStore.insert(AccountState(account: account))
        states = SharedStore.load()
        WidgetCenter.shared.reloadAllTimelines()
        Task { await self.refresh(ids: [account.id], reason: .accountAdded) }
    }

    func remove(_ account: StoredAccount) {
        KeychainStore.delete(for: account.id)
        RefreshLedgerStore.remove(accountID: account.id)
        do {
            try SharedStore.remove(id: account.id)
            states = SharedStore.load()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            AmmoLog.sharedStore.error("Unable to remove account: \(String(describing: error), privacy: .private)")
        }
    }

    // MARK: - Fetch pipeline

    @discardableResult
    func refreshAll(reason: RefreshReason = .manual) async -> [RefreshOutcome] {
        await refresh(ids: states.map(\.account.id), reason: reason)
    }

    @discardableResult
    func refresh(ids: [UUID], reason: RefreshReason = .manual) async -> [RefreshOutcome] {
#if DEBUG
        if Self.usesErrorPreview { return [] }
#endif
        guard !ids.isEmpty else { return [] }
        isRefreshing = true
        defer { isRefreshing = false }
        let outcomes = await UsageRefreshCoordinator.shared.refresh(accountIDs: ids,
                                                                     reason: reason)
        states = SharedStore.load()
        if outcomes.contains(where: \.changedSnapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        return outcomes
    }
}

#if DEBUG
private extension AccountStore {
    static var usesErrorPreview: Bool {
        ProcessInfo.processInfo.arguments.contains("--ammo-error-preview")
    }

    static var errorPreviewStates: [AccountState] {
        let now = Date()
        return [
            AccountState(
                account: StoredAccount(provider: .claude, label: "Claude"),
                snapshot: UsageSnapshot(
                    provider: .claude,
                    plan: nil,
                    windows: [
                        LimitWindow(kind: .session,
                                    label: "Session",
                                    usedPercent: 76,
                                    resetsAt: now.addingTimeInterval(1.75 * 60 * 60)),
                        LimitWindow(kind: .weekly,
                                    label: "Weekly",
                                    usedPercent: 49,
                                    resetsAt: now.addingTimeInterval(4.8 * 24 * 60 * 60)),
                    ],
                    fetchedAt: now.addingTimeInterval(-19 * 60)),
                lastError: nil,
                lastFailure: .timedOut,
                updatedAt: now.addingTimeInterval(-19 * 60)),
            AccountState(
                account: StoredAccount(provider: .cursor, label: "Cursor"),
                snapshot: UsageSnapshot(
                    provider: .cursor,
                    plan: "pro",
                    windows: [
                        LimitWindow(kind: .monthly,
                                    label: "Composer",
                                    usedPercent: 0,
                                    resetsAt: now.addingTimeInterval(12 * 24 * 60 * 60)),
                    ],
                    fetchedAt: now.addingTimeInterval(-7 * 60)),
                lastError: nil,
                lastFailure: .rateLimited,
                updatedAt: now.addingTimeInterval(-7 * 60)),
        ]
    }
}
#endif
