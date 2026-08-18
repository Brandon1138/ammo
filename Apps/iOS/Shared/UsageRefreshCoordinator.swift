import Foundation
import UsageKit

enum RefreshReason: String, Sendable {
    case accountAdded
    case background
    case foreground
    case manual

    /// User-visible app work may bypass the adaptive quiet period, but every
    /// reason still obeys the shared 60-second floor and provider backoff.
    var usesAdaptiveSchedule: Bool {
        switch self {
        case .background: true
        case .accountAdded, .foreground, .manual: false
        }
    }
}

enum RefreshOutcome: Sendable {
    case refreshed(accountID: UUID)
    case cached(accountID: UUID, nextEligibleAt: Date)
    case failed(accountID: UUID, message: String, nextEligibleAt: Date?)

    var accountID: UUID {
        switch self {
        case .refreshed(let accountID),
             .cached(let accountID, _),
             .failed(let accountID, _, _):
            accountID
        }
    }

    var requiresTimelineReload: Bool {
        switch self {
        case .refreshed, .failed: true
        case .cached: false
        }
    }
}

enum WidgetReloadPolicy {
    /// Whether a person is watching the result of this refresh. They are the
    /// cases where the app screen visibly settles on an answer, so a widget that
    /// disagrees with it reads as broken even when nothing was fetched.
    static func isUserInitiated(_ reason: RefreshReason) -> Bool {
        switch reason {
        case .accountAdded, .foreground, .manual: true
        case .background: false
        }
    }

    static func shouldReload(
        after outcomes: [RefreshOutcome],
        reason: RefreshReason,
        hasCachedSnapshot: Bool
    ) -> Bool {
        if outcomes.contains(where: \.requiresTimelineReload) { return true }
        // A user-initiated refresh can be throttled by the shared 60-second
        // floor and return only `.cached`. Reload anyway when the App Group
        // already has usable data: a newly placed or restored widget may still
        // be displaying its placeholder, and a pull-to-refresh that quietly
        // does nothing to the widget is exactly the MIK-51 report.
        return isUserInitiated(reason) && hasCachedSnapshot
    }
}

/// The app's network-fetch entry point. Child work remains structured under
/// each caller; RefreshLedgerStore coalesces overlapping app/background work.
actor UsageRefreshCoordinator {
    static let shared = UsageRefreshCoordinator()

    func refresh(accountIDs: [UUID], reason: RefreshReason) async -> [RefreshOutcome] {
        if DemoModeStore.isEnabled {
            return accountIDs.map {
                .cached(accountID: $0, nextEligibleAt: .distantFuture)
            }
        }
        return await Self.collectOutcomes(accountIDs: accountIDs) { accountID in
            await self.refresh(accountID: accountID, reason: reason)
        }
    }

    /// Provider work stays inside the caller's task tree. Cancellation from a
    /// BGTask expiration therefore reaches every account refresh and its
    /// URLSession request instead of only cancelling an outer wrapper.
    nonisolated static func collectOutcomes(
        accountIDs: [UUID],
        operation: @escaping @Sendable (UUID) async -> RefreshOutcome
    ) async -> [RefreshOutcome] {
        await withTaskGroup(of: RefreshOutcome.self) { group in
            for accountID in Set(accountIDs) {
                group.addTask {
                    await operation(accountID)
                }
            }

            var outcomes: [RefreshOutcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }
    }

    func refresh(accountID: UUID, reason: RefreshReason) async -> RefreshOutcome {
        if DemoModeStore.isEnabled {
            return .cached(accountID: accountID, nextEligibleAt: .distantFuture)
        }
        return await Self.execute(accountID: accountID, reason: reason)
    }

    private nonisolated static func execute(
        accountID: UUID,
        reason: RefreshReason
    ) async -> RefreshOutcome {
        guard !Task.isCancelled else { return cancelled(accountID) }
        guard let state = SharedStore.load()
            .first(where: { $0.account.id == accountID }),
              !AccountDeletionStore.isDeleted(accountID)
        else {
            return accountUnavailable(accountID)
        }
        let account = state.account

        guard let provider = provider(for: account) else {
            let message = "\(account.provider.displayName) is not supported yet"
            if isCurrent(account), !Task.isCancelled {
                try? SharedStore.record(failure: .unavailable, for: accountID)
            }
            return .failed(accountID: accountID, message: message, nextEligibleAt: nil)
        }
        guard var tokens = KeychainStore.load(for: accountID) else {
            let message = "No credentials in Keychain — open Ammo and re-add this account"
            if isCurrent(account), !Task.isCancelled {
                try? SharedStore.record(failure: .authentication, for: accountID)
            }
            return .failed(accountID: accountID, message: message, nextEligibleAt: nil)
        }

        guard !Task.isCancelled else { return cancelled(accountID) }
        let claim = RefreshLedgerStore.claim(accountID: accountID, reason: reason)
        guard claim.isGranted else {
            guard isCurrent(account), !Task.isCancelled else {
                return cancelledOrUnavailable(account)
            }
            AmmoLog.refresh.debug("Using cached \(account.provider.displayName, privacy: .public) usage; refresh is throttled")
            let currentState = SharedStore.load().first { $0.account == account }
            return throttledOutcome(accountID: accountID,
                                    nextEligibleAt: claim.nextEligibleAt,
                                    hasSnapshot: currentState?.snapshot != nil)
        }

        let mayRefresh = !account.tokensImported && tokens.refreshToken != nil

        do {
            try ensureActive(account)
            if mayRefresh, let expiresAt = tokens.expiresAt,
               expiresAt.timeIntervalSinceNow < 5 * 60 {
                tokens = try await provider.refresh(tokens: tokens)
                try ensureActive(account)
                try KeychainStore.save(tokens, for: accountID)
                try ensureActive(account)
            }

            var snapshot: UsageSnapshot
            do {
                snapshot = try await provider.fetchUsage(tokens: tokens)
                try ensureActive(account)
            } catch UsageError.http(let status, _) where status == 401 && mayRefresh {
                tokens = try await provider.refresh(tokens: tokens)
                try ensureActive(account)
                try KeychainStore.save(tokens, for: accountID)
                try ensureActive(account)
                snapshot = try await provider.fetchUsage(tokens: tokens)
                try ensureActive(account)
            }

            try ensureActive(account)
            guard let transition = try SharedStore.commit(snapshot: snapshot, for: accountID) else {
                throw AccountRemovedError()
            }
            try ensureActive(account)
            RefreshLedgerStore.finishSuccess(accountID: accountID,
                                             snapshot: snapshot,
                                             previousSnapshot: transition.previousSnapshot,
                                             at: snapshot.fetchedAt)
            try ensureActive(account)
            AmmoLog.refresh.info("Refreshed \(account.provider.displayName, privacy: .public) usage from \(reason.rawValue, privacy: .public)")
            return .refreshed(accountID: accountID)
        } catch is CancellationError {
            return cancelled(accountID)
        } catch is AccountRemovedError {
            return accountUnavailable(accountID)
        } catch UsageError.http(let status, _) where status == 401 && account.tokensImported {
            guard !Task.isCancelled, isCurrent(account) else {
                return cancelledOrUnavailable(account)
            }
            return fail(
                account: account,
                technicalError: "Imported token expired; re-import or sign in on-device",
                failure: .authentication,
                status: status)
        } catch let error as UsageError {
            guard !Task.isCancelled, isCurrent(account) else {
                return cancelledOrUnavailable(account)
            }
            return fail(account: account,
                        technicalError: String(describing: error),
                        failure: UsageFailureClassifier.classify(error),
                        status: error.httpStatus)
        } catch {
            guard !Task.isCancelled, isCurrent(account) else {
                return cancelledOrUnavailable(account)
            }
            return fail(account: account,
                        technicalError: String(describing: error),
                        failure: UsageFailureClassifier.classify(error),
                        status: nil)
        }
    }

    nonisolated static func throttledOutcome(
        accountID: UUID,
        nextEligibleAt: Date,
        hasSnapshot: Bool
    ) -> RefreshOutcome {
        guard hasSnapshot else {
            return .failed(accountID: accountID,
                           message: "No cached usage is available yet",
                           nextEligibleAt: nextEligibleAt)
        }
        return .cached(accountID: accountID, nextEligibleAt: nextEligibleAt)
    }

    private nonisolated static func fail(
        account: StoredAccount,
        technicalError: String,
        failure: UsageFailureKind,
        status: Int?
    ) -> RefreshOutcome {
        let accountID = account.id
        guard !Task.isCancelled, isCurrent(account) else {
            return cancelledOrUnavailable(account)
        }
        try? SharedStore.record(failure: failure, for: accountID)
        guard !Task.isCancelled, isCurrent(account) else {
            return cancelledOrUnavailable(account)
        }
        RefreshLedgerStore.finishFailure(accountID: accountID, status: status)
        let nextEligibleAt = RefreshLedgerStore.nextEligibleAt(accountID: accountID,
                                                               reason: .manual)
        AmmoLog.refresh.error("Usage refresh failed: \(technicalError, privacy: .private)")
        return .failed(accountID: accountID,
                       message: failure.rawValue,
                       nextEligibleAt: nextEligibleAt)
    }

    private nonisolated static func ensureActive(_ account: StoredAccount) throws {
        try Task.checkCancellation()
        guard isCurrent(account) else { throw AccountRemovedError() }
    }

    private nonisolated static func isCurrent(_ account: StoredAccount) -> Bool {
        !AccountDeletionStore.isDeleted(account.id)
            && SharedStore.load().contains { $0.account == account }
    }

    private nonisolated static func cancelledOrUnavailable(
        _ account: StoredAccount
    ) -> RefreshOutcome {
        Task.isCancelled ? cancelled(account.id) : accountUnavailable(account.id)
    }

    private nonisolated static func cancelled(_ accountID: UUID) -> RefreshOutcome {
        .failed(accountID: accountID,
                message: "Refresh cancelled",
                nextEligibleAt: nil)
    }

    private nonisolated static func accountUnavailable(_ accountID: UUID) -> RefreshOutcome {
        .failed(accountID: accountID,
                message: "Account no longer exists",
                nextEligibleAt: nil)
    }

    private nonisolated static func provider(for account: StoredAccount) -> (any UsageProvider)? {
        let id = account.provider
        let usageURL: URL
        switch id {
        case .claude: usageURL = ClaudeProvider.usageURL
        case .codex: usageURL = CodexProvider.usageURL
        case .cursor: usageURL = CursorProvider.usageURL
        case .openRouter: usageURL = OpenRouterProvider.usageURL
        case .antigravity: return nil
        }
        let transport = PayloadCapturingTransport(accountID: account.id,
                                                  provider: id,
                                                  usageURL: usageURL)
        return switch id {
        case .claude: ClaudeProvider(transport: transport)
        case .codex: CodexProvider(transport: transport)
        case .cursor: CursorProvider(transport: transport)
        case .openRouter: OpenRouterProvider(transport: transport)
        case .antigravity: nil
        }
    }
}

private struct AccountRemovedError: Error {}

private extension UsageError {
    var httpStatus: Int? {
        if case .http(let status, _) = self { return status }
        return nil
    }
}
