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
        states = SharedStore.load()
    }

    // MARK: - Account management

    func add(provider: ProviderID, label: String, tokens: OAuthTokens, imported: Bool) throws {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = StoredAccount(provider: provider,
                                    label: trimmed.isEmpty ? provider.displayName : trimmed,
                                    tokensImported: imported)
        try KeychainStore.save(tokens, for: account.id)
        states.append(AccountState(account: account))
        persist()
        Task { await self.refresh(ids: [account.id]) }
    }

    func remove(_ account: StoredAccount) {
        KeychainStore.delete(for: account.id)
        states.removeAll { $0.account.id == account.id }
        persist()
    }

    // MARK: - Fetch pipeline

    func refreshAll() async {
        await refresh(ids: states.map(\.account.id))
    }

    func refresh(ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for id in ids {
            await refreshOne(id: id)
        }
        persist()
    }

    private func refreshOne(id: UUID) async {
        guard let account = states.first(where: { $0.account.id == id })?.account else { return }
        guard let provider = Self.provider(for: account.provider) else {
            update(id: id) { $0.lastError = "\(account.provider.displayName) is not supported yet" }
            return
        }
        guard var tokens = KeychainStore.load(for: id) else {
            update(id: id) { $0.lastError = "No credentials in Keychain — remove and re-add this account" }
            return
        }
        // Hard rule: never refresh tokens imported from a desktop CLI — rotation
        // could invalidate the CLI's copy and log it out.
        let mayRefresh = !account.tokensImported && tokens.refreshToken != nil

        do {
            if mayRefresh, let expiresAt = tokens.expiresAt,
               expiresAt.timeIntervalSinceNow < 5 * 60 {
                tokens = try await provider.refresh(tokens: tokens)
                try KeychainStore.save(tokens, for: id) // persist rotation before anything can fail
            }
            let snapshot: UsageSnapshot
            do {
                snapshot = try await provider.fetchUsage(tokens: tokens)
            } catch UsageError.http(let status, _) where status == 401 && mayRefresh {
                tokens = try await provider.refresh(tokens: tokens)
                try KeychainStore.save(tokens, for: id)
                snapshot = try await provider.fetchUsage(tokens: tokens)
            }
            update(id: id) {
                $0.snapshot = snapshot
                $0.lastError = nil
                $0.updatedAt = Date()
            }
        } catch UsageError.http(let status, _) where status == 401 && account.tokensImported {
            update(id: id) {
                $0.lastError = "Imported token expired. Ammo never refreshes imported tokens (that could log out your desktop CLI) — re-import or sign in on-device."
            }
        } catch {
            update(id: id) { $0.lastError = String(describing: error) }
        }
    }

    private func update(id: UUID, _ mutate: (inout AccountState) -> Void) {
        guard let index = states.firstIndex(where: { $0.account.id == id }) else { return }
        mutate(&states[index])
    }

    private func persist() {
        SharedStore.save(states)
        WidgetCenter.shared.reloadAllTimelines()
    }

    nonisolated static func provider(for id: ProviderID) -> (any UsageProvider)? {
        switch id {
        case .claude: ClaudeProvider()
        case .codex: CodexProvider()
        case .cursor, .antigravity: nil // deferred, see SPEC.md
        }
    }
}
