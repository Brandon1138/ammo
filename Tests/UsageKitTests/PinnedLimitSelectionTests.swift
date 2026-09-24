import Testing
@testable import UsageKit

@Suite struct PinnedLimitSelectionTests {
    @Test func missingPinnedWindowUsesPreferredWindowFromSameAccount() throws {
        let session = LimitWindow(kind: .session, label: "Session", usedPercent: 20, resetsAt: nil)
        let weekly = LimitWindow(kind: .weekly, label: "Weekly", usedPercent: 40, resetsAt: nil)
        let otherAccount = LimitWindow(kind: .weekly, label: "Other", usedPercent: 70, resetsAt: nil)

        let selected = try #require(PinnedLimitSelection.resolve(
            windowID: "modelScoped:Spark weekly", in: [session, weekly]))
        #expect(selected.id == weekly.id)
        #expect(selected.id != otherAccount.id)
    }

    @Test func survivingPinnedWindowStaysSelected() throws {
        let session = LimitWindow(kind: .session, label: "Session", usedPercent: 20, resetsAt: nil)
        let weekly = LimitWindow(kind: .weekly, label: "Weekly", usedPercent: 40, resetsAt: nil)

        let selected = try #require(PinnedLimitSelection.resolve(
            windowID: session.id, in: [session, weekly]))
        #expect(selected.id == session.id)
    }

    @Test func accountWithoutWindowsHasNoSelection() {
        #expect(PinnedLimitSelection.resolve(windowID: "modelScoped:Spark weekly", in: []) == nil)
    }
}
