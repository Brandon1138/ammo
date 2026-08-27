import Foundation
import Testing
import UsageKit

@testable import Ammo

@Suite("Shared tab header")
struct TabHeaderConsistencyTests {
    @Test("Demo mode swaps Add Account for Exit Demo, on every tab")
    func trailingActionFollowsDemoMode() {
        #expect(AmmoHeaderTrailingAction.resolve(isDemoMode: true) == .exitDemo)
        #expect(AmmoHeaderTrailingAction.resolve(isDemoMode: false) == .addAccount)
    }

    @Test("One sheet route covers Settings, Add Account, reorder, and reconnect")
    func sheetRouteIdentifiersAreDistinctAndStable() {
        let account = StoredAccount(provider: .codex, label: "Work Codex")
        var sheets: [AmmoTabSheet] = [.settings, .reorder, .reconnect(account)]
        sheets.append(contentsOf: ProviderID.supported.map { AmmoTabSheet.addProvider($0) })

        let ids = sheets.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(AmmoTabSheet.settings.id == "settings")
        #expect(AmmoTabSheet.reorder.id == "reorder")
        #expect(AmmoTabSheet.reconnect(account).id == "reconnect-\(account.id.uuidString)")
        for provider in ProviderID.supported {
            #expect(AmmoTabSheet.addProvider(provider).id == "add-\(provider.rawValue)")
        }
    }
}
