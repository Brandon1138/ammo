import Foundation
import Testing

@testable import Ammo

@Suite("MIK-110 widget first load")
struct MIK110Tests {
    private let accountID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

    @Test("Foreground cache hit reloads a placeholder widget")
    func foregroundCacheHitReloads() {
        let outcomes: [RefreshOutcome] = [
            .cached(accountID: accountID, nextEligibleAt: .distantFuture),
        ]

        #expect(WidgetReloadPolicy.shouldReload(
            after: outcomes,
            reason: .foreground,
            hasCachedSnapshot: true))
    }

    @Test("Passive cache hit does not spend widget reload budget")
    func backgroundCacheHitDoesNotReload() {
        let outcomes: [RefreshOutcome] = [
            .cached(accountID: accountID, nextEligibleAt: .distantFuture),
        ]

        #expect(!WidgetReloadPolicy.shouldReload(
            after: outcomes,
            reason: .background,
            hasCachedSnapshot: true))
    }

    @Test("Fresh snapshots and visible failures always reload")
    func mutationsReload() {
        #expect(WidgetReloadPolicy.shouldReload(
            after: [.refreshed(accountID: accountID)],
            reason: .background,
            hasCachedSnapshot: true))
        #expect(WidgetReloadPolicy.shouldReload(
            after: [.failed(accountID: accountID,
                            message: "network",
                            nextEligibleAt: nil)],
            reason: .manual,
            hasCachedSnapshot: false))
    }
}
