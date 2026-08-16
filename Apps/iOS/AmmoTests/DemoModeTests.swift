import Foundation
import Testing
import UsageKit
@testable import Ammo

@Suite("Offline demo mode")
struct DemoModeTests {
    @Test("Demo covers every shipping provider and main data surface")
    func fixturesAreReviewable() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let states = DemoData.states(now: now)
        let history = DemoData.historySamples(now: now)

        #expect(Set(states.map(\.account.provider)) == Set(ProviderID.supported))
        #expect(states.filter { $0.account.provider != .openRouter }
            .allSatisfy { $0.snapshot?.windows.isEmpty == false })
        #expect(states.first { $0.account.provider == .openRouter }?.snapshot?.windows == [])
        #expect(states.allSatisfy { $0.snapshot?.onDemand?.isEmpty == false })
        #expect(history.count == states.count * 84)
        #expect(Set(history.map(\.accountID)) == Set(states.map(\.id)))
    }
}
