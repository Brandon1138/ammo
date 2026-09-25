import Foundation
import Testing
import UsageKit
@testable import Ammo

@MainActor
@Suite("Lock Screen gauge")
struct LockScreenGaugeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Codex Pro weekly window uses neutral marker gauge")
    func proPlanUsesWeeklyWindow() throws {
        let state = AccountState(
            account: StoredAccount(provider: .codex, label: "Codex"),
            snapshot: UsageSnapshot(
                provider: .codex,
                plan: "prolite",
                windows: [LimitWindow(kind: .weekly, label: "Weekly", usedPercent: 100,
                                      resetsAt: nil)],
                fetchedAt: now),
            lastError: nil,
            updatedAt: now)

        let presentation = try #require(state.lockScreenUsagePresentation)
        #expect(presentation.indicatorWindow.label == "Weekly")
        #expect(presentation.numericWindow == nil)
    }
}
