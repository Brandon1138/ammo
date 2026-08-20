import Foundation
import Observation
import UsageKit

/// Source of truth for accounts and their latest usage. Persists to the App
/// Group (SharedStore) so widgets see every change; tokens go to the Keychain.
@MainActor @Observable
final class AccountStore {
    static let shared = AccountStore()

    private(set) var states: [AccountState]
    private(set) var historySamples: [UsageHistorySample]
    private(set) var retryStates: [UUID: AccountRetryState] = [:]
    private var refreshGenerations: [UUID: UInt] = [:]

    var isRefreshing: Bool {
        retryStates.values.contains(.refreshing)
    }

    var isDemoMode: Bool { DemoModeStore.isEnabled }

    /// Display preferences change what is drawn, not what is fetched, so the
    /// setter republishes the cache the app already holds and tells WidgetKit
    /// to redraw. Nothing here triggers a network round trip.
    var showsCodexSpark: Bool { UsageDisplayPreferences.showsCodexSpark }

    func setShowsCodexSpark(_ enabled: Bool) {
        do {
            try UsageDisplayPreferences.setShowsCodexSpark(enabled)
        } catch {
            AmmoLog.sharedStore.error("Unable to store Codex Spark display preference: \(String(describing: error), privacy: .private)")
            return
        }
        states = SharedStore.load()
        WidgetInvalidator.shared.invalidate(reason: .displayPreferenceChanged)
    }

    private init() {
#if targetEnvironment(simulator)
        if Self.usesHistoryPreview {
            states = Self.historyPreviewStates
            historySamples = Self.historyPreviewSamples
            return
        }
        if Self.usesErrorPreview {
            states = Self.errorPreviewStates
            historySamples = []
            retryStates = Self.errorPreviewRetryStates(for: states)
            return
        }
#endif
        AccountMutationStore.recoverPending()
        states = SharedStore.load()
        historySamples = UsageHistoryStore.load()
        retryStates = Dictionary(uniqueKeysWithValues: states.map { state in
            let eligibleAt = RefreshLedgerStore.nextEligibleAt(accountID: state.id,
                                                                reason: .manual)
            return (state.id, eligibleAt.map(AccountRetryState.coolingDown) ?? .ready)
        })
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
        try AccountMutationStore.begin(.adding, account: account)
        do {
            try KeychainStore.save(tokens, for: account.id)
            try SharedStore.insert(AccountState(account: account))
        } catch {
            do {
                try AccountMutationStore.rollBackAdd(account)
            } catch {
                AmmoLog.sharedStore.error("Account add rollback remains pending: \(String(describing: error), privacy: .private)")
            }
            throw error
        }
        do {
            try AccountMutationStore.finish(accountID: account.id)
        } catch {
            // Both durable stores committed. Journal recovery will recognize
            // this complete add and remove only the stale transaction record.
            AmmoLog.sharedStore.error("Account add journal cleanup deferred: \(String(describing: error), privacy: .private)")
        }
        states = SharedStore.load()
        Task { await self.refresh(ids: [account.id], reason: .accountAdded) }
    }

    func remove(_ account: StoredAccount) {
        var needsCallerInvalidation = false
        do {
            try AccountMutationStore.begin(.removing, account: account)
            try AccountMutationStore.finishRemoval(account)
        } catch {
            needsCallerInvalidation = AccountMutationStore.needsCallerInvalidation(after: error)
            // Durable journal or tombstone preserves intent. Recovery retries
            // any unfinished cleanup; reload now so tombstoned state vanishes.
            AmmoLog.sharedStore.error("Account removal cleanup remains pending: \(String(describing: error), privacy: .private)")
        }
        states = SharedStore.load()
        historySamples = UsageHistoryStore.load()
        // Successful removal already invalidated after SharedStore committed its
        // bytes. Only the deferred-cleanup path needs a caller-side reload so a
        // newly written tombstone hides the stale cached account immediately.
        if needsCallerInvalidation {
            WidgetInvalidator.shared.invalidate(reason: .accountRemoved)
        }
        Task { await self.refresh(ids: []) }
    }

    func enableDemoMode() {
        do {
            try DemoModeStore.setEnabled(true)
            states = UsageDisplayPreferences.presented(DemoData.states())
            historySamples = DemoData.historySamples()
            retryStates = [:]
            WidgetInvalidator.shared.invalidate(reason: .demoModeChanged)
        } catch {
            AmmoLog.sharedStore.error("Unable to enable demo mode: \(String(describing: error), privacy: .private)")
        }
    }

    func disableDemoMode() {
        do {
            try DemoModeStore.setEnabled(false)
        } catch {
            AmmoLog.sharedStore.error("Unable to disable demo mode: \(String(describing: error), privacy: .private)")
            return
        }
        states = SharedStore.load()
        historySamples = UsageHistoryStore.load()
        retryStates = [:]
        WidgetInvalidator.shared.invalidate(reason: .demoModeChanged)
    }

    /// Publishes whatever the App Group already holds, without waiting for a
    /// network round trip.
    ///
    /// Opening Ammo is the moment a person expects their widgets to agree with
    /// the app, and a widget placed while the app was closed has never been told
    /// the cache exists. Waiting for `refreshAll` to finish first makes that
    /// wait as long as the slowest provider — or unbounded when the device is
    /// offline. Ordering is safe: the cache being republished was committed by
    /// an earlier write.
    func invalidateWidgetsFromCache(reason: WidgetInvalidationReason = .appForeground) {
        WidgetInvalidator.shared.invalidate(
            reason: reason,
            revision: SharedStoreRevisionStore.load())
    }

    // MARK: - Fetch pipeline

    @discardableResult
    func refreshAll(reason: RefreshReason = .manual) async -> [RefreshOutcome] {
        await refresh(ids: states.map(\.account.id), reason: reason)
    }

    @discardableResult
    func refresh(ids: [UUID], reason: RefreshReason = .manual) async -> [RefreshOutcome] {
#if targetEnvironment(simulator)
        if Self.usesErrorPreview || Self.usesHistoryPreview { return [] }
#endif
        if isDemoMode { return [] }
        guard !ids.isEmpty else {
            await UsageNotificationService.shared.process(
                snapshots: Dictionary(uniqueKeysWithValues: states.compactMap { state in
                    state.snapshot.map { (state.id, $0) }
                }),
                refreshedAccountIDs: [],
                knownAccountIDs: Set(states.map(\.id))
            )
            return []
        }
        let uniqueIDs = Array(Set(ids))
        var generations: [UUID: UInt] = [:]
        for id in uniqueIDs {
            let generation = (refreshGenerations[id] ?? 0) &+ 1
            refreshGenerations[id] = generation
            generations[id] = generation
            retryStates[id] = .refreshing
        }
        let outcomes = await UsageRefreshCoordinator.shared.refresh(accountIDs: uniqueIDs,
                                                                     reason: reason)
        states = SharedStore.load()
        historySamples = UsageHistoryStore.load()
        let outcomesByID = Dictionary(uniqueKeysWithValues: outcomes.map { ($0.accountID, $0) })
        for id in uniqueIDs where refreshGenerations[id] == generations[id] {
            retryStates[id] = outcomesByID[id].map(AccountRetryState.init(outcome:)) ?? .ready
        }
        // Persisted outcomes already reload through the SharedStore write seam.
        // Cache-only manual/account-add outcomes reload here because no write
        // occurred. Foreground already republished the cache on activation.
        let hasCachedSnapshot = states.contains { state in
            uniqueIDs.contains(state.id) && state.snapshot != nil
        }
        if WidgetReloadPolicy.shouldReload(after: outcomes,
                                           reason: reason,
                                           hasCachedSnapshot: hasCachedSnapshot) {
            WidgetInvalidator.shared.invalidate(
                reason: .refreshFinished,
                revision: SharedStoreRevisionStore.load())
        }
        let refreshedAccountIDs = Set(outcomes.compactMap { outcome -> UUID? in
            guard case .refreshed(let accountID) = outcome else { return nil }
            return accountID
        })
        await UsageNotificationService.shared.process(
            snapshots: Dictionary(uniqueKeysWithValues: states.compactMap { state in
                state.snapshot.map { (state.id, $0) }
            }),
            refreshedAccountIDs: refreshedAccountIDs,
            knownAccountIDs: Set(states.map(\.id))
        )
        return outcomes
    }

    func retryState(for accountID: UUID, at date: Date) -> AccountRetryState {
        guard let state = retryStates[accountID] else { return .ready }
        if case .coolingDown(let eligibleAt) = state, eligibleAt <= date {
            return .ready
        }
        return state
    }

    func reloadHistory() {
#if targetEnvironment(simulator)
        if Self.usesHistoryPreview {
            historySamples = Self.historyPreviewSamples
            return
        }
#endif
        historySamples = UsageHistoryStore.load()
    }

#if targetEnvironment(simulator)
    func installHistoryPreview() {
        states = Self.historyPreviewStates
        historySamples = Self.historyPreviewSamples
    }
#endif
}

#if targetEnvironment(simulator)
private extension AccountStore {
    static var usesHistoryPreview: Bool {
        ProcessInfo.processInfo.arguments.contains("--ammo-history-preview")
            || ProcessInfo.processInfo.environment["AMMO_HISTORY_PREVIEW"] == "1"
            || UserDefaults.standard.bool(forKey: "AmmoHistoryPreview")
    }

    static var usesErrorPreview: Bool {
        ProcessInfo.processInfo.arguments.contains("--ammo-error-preview")
    }

    static func errorPreviewRetryStates(for states: [AccountState]) -> [UUID: AccountRetryState] {
        let arguments = ProcessInfo.processInfo.arguments
        let state: AccountRetryState
        if arguments.contains("--ammo-error-preview-refreshing") {
            state = .refreshing
        } else if arguments.contains("--ammo-error-preview-cooldown") {
            state = .coolingDown(until: Date().addingTimeInterval(42))
        } else {
            state = .ready
        }
        return Dictionary(uniqueKeysWithValues: states.map { ($0.id, state) })
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

    static var historyPreviewStates: [AccountState] {
        let now = Date()
        return [
            AccountState(
                account: StoredAccount(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    provider: .codex,
                    label: "Codex"
                ),
                snapshot: UsageSnapshot(
                    provider: .codex,
                    plan: "self_serve_business_usage_based",
                    windows: [
                        LimitWindow(kind: .weekly,
                                    label: "Weekly",
                                    usedPercent: 71,
                                    resetsAt: now.addingTimeInterval(5.6 * 24 * 60 * 60)),
                    ],
                    onDemand: [
                        OnDemandUsage(id: "codex-usage-credits",
                                      label: "Usage credits",
                                      kind: .creditBalance,
                                      scope: .organization,
                                      isEnabled: true,
                                      unit: .credits,
                                      currencyCode: "",
                                      remaining: 21_062.8748975,
                                      expiresAt: now.addingTimeInterval(8 * 24 * 60 * 60),
                                      equivalentAmount: 3_622.81,
                                      equivalentCurrencyCode: "RON"),
                        OnDemandUsage(id: "codex-individual-limit",
                                      label: "Personal limit",
                                      kind: .personalAllocation,
                                      scope: .personal,
                                      isEnabled: true,
                                      used: 37.50,
                                      limit: 100,
                                      remaining: 62.50,
                                      resetsAt: now.addingTimeInterval(9 * 24 * 60 * 60)),
                    ],
                    fetchedAt: now
                ),
                lastError: nil,
                lastFailure: nil,
                updatedAt: now
            ),
            AccountState(
                account: StoredAccount(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    provider: .claude,
                    label: "Claude"
                ),
                snapshot: UsageSnapshot(
                    provider: .claude,
                    plan: "max",
                    windows: [
                        LimitWindow(kind: .session,
                                    label: "Session",
                                    usedPercent: 67,
                                    resetsAt: now.addingTimeInterval(3.7 * 60 * 60)),
                        LimitWindow(kind: .weekly,
                                    label: "Weekly",
                                    usedPercent: 67,
                                    resetsAt: now.addingTimeInterval(3.4 * 24 * 60 * 60)),
                    ],
                    onDemand: [
                        OnDemandUsage(id: "claude-extra-usage",
                                      label: "Extra usage",
                                      kind: .spendingLimit,
                                      scope: .personal,
                                      isEnabled: true,
                                      currencyCode: "EUR",
                                      used: 7.63,
                                      limit: 20,
                                      remaining: 12.37,
                                      usedPercent: 38.15),
                    ],
                    fetchedAt: now
                ),
                lastError: nil,
                lastFailure: nil,
                updatedAt: now
            ),
            AccountState(
                account: StoredAccount(
                    id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                    provider: .cursor,
                    label: "Cursor Enterprise"
                ),
                snapshot: UsageSnapshot(
                    provider: .cursor,
                    plan: "enterprise",
                    windows: [
                        LimitWindow(kind: .monthly,
                                    label: "Composer",
                                    usedPercent: 42,
                                    resetsAt: now.addingTimeInterval(12 * 24 * 60 * 60)),
                        LimitWindow(kind: .monthly,
                                    label: "API",
                                    usedPercent: 18,
                                    resetsAt: now.addingTimeInterval(12 * 24 * 60 * 60)),
                    ],
                    onDemand: [
                        OnDemandUsage(id: "cursor-personal-on-demand",
                                      label: "Personal on-demand",
                                      kind: .spendingLimit,
                                      scope: .personal,
                                      isEnabled: true,
                                      used: 5.50,
                                      limit: 50,
                                      remaining: 44.50,
                                      resetsAt: now.addingTimeInterval(12 * 24 * 60 * 60)),
                        OnDemandUsage(id: "cursor-personal-allocation",
                                      label: "Personal allocation",
                                      kind: .personalAllocation,
                                      scope: .personal,
                                      isEnabled: true,
                                      used: 73.84,
                                      limit: 100,
                                      remaining: 26.16,
                                      resetsAt: now.addingTimeInterval(12 * 24 * 60 * 60)),
                        OnDemandUsage(id: "cursor-team-on-demand",
                                      label: "Team on-demand",
                                      kind: .teamBudget,
                                      scope: .team,
                                      isEnabled: true,
                                      used: 25,
                                      limit: 250,
                                      remaining: 225,
                                      resetsAt: now.addingTimeInterval(12 * 24 * 60 * 60)),
                        OnDemandUsage(id: "cursor-shared-pool",
                                      label: "Shared pool",
                                      kind: .pooledBudget,
                                      scope: .organization,
                                      isEnabled: true,
                                      used: 1_200,
                                      limit: 5_000,
                                      remaining: 3_800,
                                      resetsAt: now.addingTimeInterval(12 * 24 * 60 * 60)),
                    ],
                    fetchedAt: now
                ),
                lastError: nil,
                lastFailure: nil,
                updatedAt: now
            ),
        ]
    }

    static var historyPreviewSamples: [UsageHistorySample] {
        historyPreviewStates.flatMap { state -> [UsageHistorySample] in
            guard let snapshot = state.snapshot else { return [] }
            return (-83...0).map { dayOffset in
                let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
                let daysFromStart = dayOffset + 83
                let cycleDay = daysFromStart % 7
                let resetDate = Calendar.current.date(byAdding: .day,
                                                      value: 7 - cycleDay,
                                                      to: Calendar.current.startOfDay(for: date))
                let windows = snapshot.windows.map { window in
                    let activity = Double((daysFromStart * (state.account.provider == .codex ? 7 : 11)) % 16)
                    let used = min(96, Double(cycleDay * 11) + activity)
                    return LimitWindow(kind: window.kind,
                                       label: window.label,
                                       usedPercent: used,
                                       resetsAt: resetDate)
                }
                return UsageHistorySample(
                    accountID: state.id,
                    snapshot: UsageSnapshot(provider: snapshot.provider,
                                            plan: snapshot.plan,
                                            windows: windows,
                                            onDemand: snapshot.onDemand,
                                            fetchedAt: date)
                )
            }
        }
    }
}
#endif
