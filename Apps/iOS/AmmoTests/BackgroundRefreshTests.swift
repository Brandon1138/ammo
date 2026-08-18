import Foundation
import Testing
import UsageKit
@testable import Ammo

/// iOS budgets future BGAppRefreshTask runs on the outcome we report, so a run
/// that fetched nothing must not be reported as a success.
@Suite("Background refresh outcome")
struct BackgroundRefreshOutcomeTests {
    private let first = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let second = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    @Test("A run where every account failed is not a success")
    func allFailuresAreReportedAsFailure() {
        let outcomes: [RefreshOutcome] = [
            .failed(accountID: first, message: "network", nextEligibleAt: nil, didPersist: true),
            .failed(accountID: second, message: "authentication", nextEligibleAt: nil, didPersist: true),
        ]

        #expect(!BackgroundRefresh.didSucceed(outcomes: outcomes))
    }

    @Test("One refreshed account carries the run")
    func partialSuccessIsASuccess() {
        let outcomes: [RefreshOutcome] = [
            .refreshed(accountID: first),
            .failed(accountID: second, message: "network", nextEligibleAt: nil, didPersist: true),
        ]

        #expect(BackgroundRefresh.didSucceed(outcomes: outcomes))
    }

    @Test("A deliberately throttled run is a success — the cached snapshot is current")
    func cachedOnlyIsASuccess() {
        let outcomes: [RefreshOutcome] = [
            .cached(accountID: first, nextEligibleAt: Date(timeIntervalSince1970: 1_000)),
        ]

        #expect(BackgroundRefresh.didSucceed(outcomes: outcomes))
    }

    @Test("A throttled account without a snapshot is a failure, not cached success")
    func noCacheDuringBackoffIsAFailure() {
        let nextEligibleAt = Date(timeIntervalSince1970: 1_000)
        let outcome = UsageRefreshCoordinator.throttledOutcome(
            accountID: first,
            nextEligibleAt: nextEligibleAt,
            hasSnapshot: false)

        guard case .failed(let accountID, _, let retryAt, _) = outcome else {
            Issue.record("Expected no-cache throttle to fail")
            return
        }
        #expect(accountID == first)
        #expect(retryAt == nextEligibleAt)
        #expect(!BackgroundRefresh.didSucceed(outcomes: [outcome]))
    }

    @Test("First failure creates backoff, and its retry has no cached success")
    func firstFailureBackoffWithoutSnapshot() {
        let accountID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        defer { RefreshLedgerStore.remove(accountID: accountID) }

        let firstClaim = RefreshLedgerStore.claim(accountID: accountID,
                                                  reason: .background,
                                                  now: now)
        #expect(firstClaim.isGranted)
        RefreshLedgerStore.finishFailure(accountID: accountID, status: nil, at: now)

        let retryClaim = RefreshLedgerStore.claim(accountID: accountID,
                                                  reason: .background,
                                                  now: now.addingTimeInterval(1))
        #expect(!retryClaim.isGranted)
        let outcome = UsageRefreshCoordinator.throttledOutcome(
            accountID: accountID,
            nextEligibleAt: retryClaim.nextEligibleAt,
            hasSnapshot: false)
        guard case .failed(_, _, let nextEligibleAt, _) = outcome else {
            Issue.record("Expected first-failure backoff without a snapshot")
            return
        }
        #expect(nextEligibleAt == now.addingTimeInterval(60))
    }

    @Test("No accounts is vacuously a success — there was nothing to fetch")
    func emptyRunIsASuccess() {
        #expect(BackgroundRefresh.didSucceed(outcomes: []))
    }

    @Test("Structured account work receives parent cancellation")
    func cancellationPropagatesToProviderWork() async {
        let probe = StructuredCancellationProbe()
        let work = Task {
            await UsageRefreshCoordinator.collectOutcomes(accountIDs: [first, second]) { id in
                await probe.run(accountID: id)
            }
        }

        for _ in 0..<100 {
            if await probe.hasStarted { break }
            await Task.yield()
        }
        work.cancel()
        _ = await work.value

        let cancelledCount = await probe.cancelledCount
        #expect(cancelledCount == 2)
    }

    @Test("Completion latch can be claimed exactly once under contention")
    func completionIsExactlyOnce() async {
        let latch = CompletionLatch()
        let claims = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<100 {
                group.addTask { latch.claim() }
            }
            var claims: [Bool] = []
            for await claim in group {
                claims.append(claim)
            }
            return claims
        }

        #expect(claims.filter { $0 }.count == 1)
    }
}

private actor StructuredCancellationProbe {
    private(set) var startedCount = 0
    private(set) var cancelledCount = 0

    var hasStarted: Bool { startedCount > 0 }

    func run(accountID: UUID) async -> RefreshOutcome {
        startedCount += 1
        while !Task.isCancelled {
            await Task.yield()
        }
        cancelledCount += 1
        return .failed(accountID: accountID,
                       message: "cancelled",
                       nextEligibleAt: nil,
                       didPersist: false)
    }
}

/// The refresh pipeline persists a rotated token pair before the next refresh
/// reads it back. A rotation that does not survive the Keychain round trip logs
/// the account out on the following cycle, which is invisible until it happens.
@Suite("Rotated credential persistence", .serialized)
struct RotatedCredentialPersistenceTests {
    private func withTemporaryAccount(_ body: (UUID) throws -> Void) rethrows {
        let id = UUID()
        defer { KeychainStore.delete(for: id) }
        try body(id)
    }

    @Test("A rotated Cursor pair is what the next refresh loads")
    func rotationSurvivesTheKeychain() throws {
        try withTemporaryAccount { id in
            let initial = OAuthTokens(accessToken: "access-1",
                                      refreshToken: "refresh-1",
                                      expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
                                      accountID: "user_ABC")
            try KeychainStore.save(initial, for: id)
            #expect(KeychainStore.load(for: id) == initial)

            // What CursorProvider.refresh returns when the server rotates.
            let rotated = OAuthTokens(accessToken: "access-2",
                                      refreshToken: "refresh-2",
                                      expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
                                      accountID: "user_ABC")
            try KeychainStore.save(rotated, for: id)

            let loaded = try #require(KeychainStore.load(for: id))
            #expect(loaded == rotated)
            #expect(loaded.refreshToken == "refresh-2")
        }
    }

    @Test("A rotation that reuses the access token as the refresh credential persists too")
    func accessTokenPromotedToRefreshCredentialPersists() throws {
        try withTemporaryAccount { id in
            try KeychainStore.save(OAuthTokens(accessToken: "access-1",
                                               refreshToken: "refresh-1"), for: id)
            // Cursor omits refresh_token: the new access token becomes the next
            // refresh credential (CursorProvider.refresh).
            let promoted = OAuthTokens(accessToken: "access-2", refreshToken: "access-2")
            try KeychainStore.save(promoted, for: id)

            let loaded = try #require(KeychainStore.load(for: id))
            #expect(loaded.refreshToken == "access-2")
            #expect(loaded.expiresAt == nil)
        }
    }

    @Test("Removing an account leaves no credential behind")
    func deleteRemovesTheCredential() throws {
        let id = UUID()
        try KeychainStore.save(OAuthTokens(accessToken: "access-1", refreshToken: "refresh-1"),
                               for: id)
        KeychainStore.delete(for: id)

        #expect(KeychainStore.load(for: id) == nil)
    }
}
