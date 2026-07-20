import Foundation
import UsageKit

enum RefreshReason: String, Sendable {
    case accountAdded
    case background
    case foreground
    case manual
    case widget

    /// User-visible app work may bypass the adaptive quiet period, but every
    /// reason still obeys the shared 60-second floor and provider backoff.
    var usesAdaptiveSchedule: Bool {
        switch self {
        case .background, .widget: true
        case .accountAdded, .foreground, .manual: false
        }
    }
}

enum RefreshOutcome: Sendable {
    case refreshed(accountID: UUID)
    case cached(accountID: UUID, nextEligibleAt: Date)
    case failed(accountID: UUID, message: String)

    var changedSnapshot: Bool {
        if case .refreshed = self { return true }
        return false
    }
}

/// The only network-fetch entry point for both the app and widget extension.
/// The actor coalesces work within a process; RefreshLedgerStore enforces the
/// same 60-second rule across the two independent processes.
actor UsageRefreshCoordinator {
    static let shared = UsageRefreshCoordinator()

    private var inFlight: [UUID: Task<RefreshOutcome, Never>] = [:]

    func refresh(accountIDs: [UUID], reason: RefreshReason) async -> [RefreshOutcome] {
        await withTaskGroup(of: RefreshOutcome.self) { group in
            for accountID in Set(accountIDs) {
                group.addTask {
                    await self.refresh(accountID: accountID, reason: reason)
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
        if let task = inFlight[accountID] {
            return await task.value
        }

        let task = Task {
            await Self.execute(accountID: accountID, reason: reason)
        }
        inFlight[accountID] = task
        let outcome = await task.value
        inFlight[accountID] = nil
        return outcome
    }

    private nonisolated static func execute(
        accountID: UUID,
        reason: RefreshReason
    ) async -> RefreshOutcome {
        guard let account = SharedStore.load()
            .first(where: { $0.account.id == accountID })?.account
        else {
            return .failed(accountID: accountID, message: "Account no longer exists")
        }

        guard let provider = provider(for: account.provider) else {
            let message = "\(account.provider.displayName) is not supported yet"
            try? SharedStore.record(failure: .unavailable, for: accountID)
            return .failed(accountID: accountID, message: message)
        }
        guard var tokens = KeychainStore.load(for: accountID) else {
            let message = "No credentials in Keychain — open Ammo and re-add this account"
            try? SharedStore.record(failure: .authentication, for: accountID)
            return .failed(accountID: accountID, message: message)
        }

        let claim = RefreshLedgerStore.claim(accountID: accountID, reason: reason)
        guard claim.isGranted else {
            AmmoLog.refresh.debug("Using cached \(account.provider.displayName, privacy: .public) usage; refresh is throttled")
            return .cached(accountID: accountID, nextEligibleAt: claim.nextEligibleAt)
        }

        let mayRefresh = !account.tokensImported && tokens.refreshToken != nil

        do {
            if mayRefresh, let expiresAt = tokens.expiresAt,
               expiresAt.timeIntervalSinceNow < 5 * 60 {
                tokens = try await provider.refresh(tokens: tokens)
                try KeychainStore.save(tokens, for: accountID)
            }

            let snapshot: UsageSnapshot
            do {
                snapshot = try await provider.fetchUsage(tokens: tokens)
            } catch UsageError.http(let status, _) where status == 401 && mayRefresh {
                tokens = try await provider.refresh(tokens: tokens)
                try KeychainStore.save(tokens, for: accountID)
                snapshot = try await provider.fetchUsage(tokens: tokens)
            }

            let transition = try SharedStore.commit(snapshot: snapshot, for: accountID)
            RefreshLedgerStore.finishSuccess(accountID: accountID,
                                             snapshot: snapshot,
                                             previousSnapshot: transition?.previousSnapshot,
                                             at: snapshot.fetchedAt)
            AmmoLog.refresh.info("Refreshed \(account.provider.displayName, privacy: .public) usage from \(reason.rawValue, privacy: .public)")
            return .refreshed(accountID: accountID)
        } catch UsageError.http(let status, _) where status == 401 && account.tokensImported {
            return fail(
                accountID: accountID,
                technicalError: "Imported token expired; re-import or sign in on-device",
                failure: .authentication,
                status: status)
        } catch let error as UsageError {
            return fail(accountID: accountID,
                        technicalError: String(describing: error),
                        failure: UsageFailureClassifier.classify(error),
                        status: error.httpStatus)
        } catch {
            return fail(accountID: accountID,
                        technicalError: String(describing: error),
                        failure: UsageFailureClassifier.classify(error),
                        status: nil)
        }
    }

    private nonisolated static func fail(
        accountID: UUID,
        technicalError: String,
        failure: UsageFailureKind,
        status: Int?
    ) -> RefreshOutcome {
        try? SharedStore.record(failure: failure, for: accountID)
        RefreshLedgerStore.finishFailure(accountID: accountID, status: status)
        AmmoLog.refresh.error("Usage refresh failed: \(technicalError, privacy: .private)")
        return .failed(accountID: accountID, message: failure.rawValue)
    }

    private nonisolated static func provider(for id: ProviderID) -> (any UsageProvider)? {
        switch id {
        case .claude: ClaudeProvider()
        case .codex: CodexProvider()
        case .cursor: CursorProvider()
        case .antigravity: nil
        }
    }
}

private extension UsageError {
    var httpStatus: Int? {
        if case .http(let status, _) = self { return status }
        return nil
    }
}
