import Testing
@testable import Ammo

@Suite("MIK-45 tab selection")
struct TabSelectionPolicyTests {
    @Test("Normal launch prepares Usage before first activation")
    func normalLaunchPreparesUsage() {
        let selection = TabSelectionState(initialTab: .usage)

        #expect(selection.selectedTab == .usage)
    }

    @Test("Entering background prepares Usage before foregrounding")
    func foregroundAfterHistoryPreparesUsage() {
        var selection = TabSelectionState(initialTab: .usage)
        selection.sceneDidBecomeActive()
        selection.select(.history)

        selection.scenePhaseChanged(to: .background)

        #expect(selection.selectedTab == .usage)
        selection.sceneDidBecomeActive()
        #expect(selection.selectedTab == .usage)
    }

    @Test("Inactive-only interruption preserves the visible tab")
    func inactiveInterruptionPreservesHistory() {
        var selection = TabSelectionState(initialTab: .usage)
        selection.sceneDidBecomeActive()
        selection.select(.history)

        selection.scenePhaseChanged(to: .inactive)

        #expect(selection.selectedTab == .history)
        selection.sceneDidBecomeActive()
        #expect(selection.selectedTab == .history)
    }

    @Test("Inactive History link prepares History for next activation")
    func inactiveHistoryLinkWinsNextActivation() {
        var selection = TabSelectionState(initialTab: .usage)
        selection.sceneDidBecomeActive()
        selection.scenePhaseChanged(to: .background)

        selection.openHistory(isSceneActive: false)
        selection.scenePhaseChanged(to: .background)

        #expect(selection.selectedTab == .history)
        selection.sceneDidBecomeActive()
        #expect(selection.selectedTab == .history)
    }

    @Test("Active History link selects History immediately")
    func activeHistoryLinkSelectsImmediately() {
        var selection = TabSelectionState(initialTab: .usage)
        selection.sceneDidBecomeActive()

        selection.openHistory(isSceneActive: true)

        #expect(selection.selectedTab == .history)
    }

    @Test("Preview tab is limited to initial activation")
    func previewDoesNotRestoreAfterForegrounding() {
        var selection = TabSelectionState(initialTab: .history)

        selection.scenePhaseChanged(to: .background)
        #expect(selection.selectedTab == .history)
        selection.sceneDidBecomeActive()
        #expect(selection.selectedTab == .history)

        selection.scenePhaseChanged(to: .background)
        #expect(selection.selectedTab == .usage)
        selection.sceneDidBecomeActive()
        #expect(selection.selectedTab == .usage)
    }
}
