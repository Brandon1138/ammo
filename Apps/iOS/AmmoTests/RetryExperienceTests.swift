import Foundation
import Testing
@testable import Ammo

@Suite("Retry experience")
struct RetryExperienceTests {
    private let accountID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

    @Test("A blocked tap preserves the provider eligibility time")
    func cooldownOutcome() {
        let eligibleAt = Date(timeIntervalSince1970: 1_000)
        let state = AccountRetryState(outcome: .cached(accountID: accountID,
                                                       nextEligibleAt: eligibleAt))

        #expect(state == .coolingDown(until: eligibleAt))
        #expect(state.resolved(at: eligibleAt.addingTimeInterval(-1)).isCoolingDown)
    }

    @Test("A cooldown becomes retryable at its eligibility time")
    func eligibleCooldown() {
        let eligibleAt = Date(timeIntervalSince1970: 1_000)
        let state = AccountRetryState.coolingDown(until: eligibleAt)

        #expect(state.resolved(at: eligibleAt) == .ready)
    }

    @Test("An accepted retry has an explicit in-progress state")
    func retryInProgress() {
        #expect(AccountRetryState.refreshing == .refreshing)
        #expect(!AccountRetryState.refreshing.isCoolingDown)
    }

    @Test("Success clears retry state")
    func successfulRetry() {
        let state = AccountRetryState(outcome: .refreshed(accountID: accountID))

        #expect(state == .ready)
    }

    @Test("Repeated failures use increasing ledger backoff up to fifteen minutes")
    func repeatedFailure() {
        let delays = (1...6).map {
            RefreshFailureBackoff.delay(consecutiveFailures: $0, status: nil)
        }

        #expect(delays == [60, 120, 240, 480, 900, 900])
    }
}
