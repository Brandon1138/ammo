import Testing
@testable import Ammo

@Suite("MIK-45 tab selection")
struct TabSelectionPolicyTests {
    @Test("Normal cold launch starts on Usage")
    func coldLaunchUsesUsage() {
        #expect(
            TabSelectionPolicy.tabForSceneActivation(
                isInitialActivation: true,
                initialTab: .usage,
                hasPendingHistoryLink: false) == .usage)
    }

    @Test("Foregrounding resets stale History selection to Usage")
    func foregroundUsesUsage() {
        #expect(
            TabSelectionPolicy.tabForSceneActivation(
                isInitialActivation: false,
                initialTab: .usage,
                hasPendingHistoryLink: false) == .usage)
    }

    @Test("Explicit History link wins during scene activation")
    func pendingHistoryLinkUsesHistory() {
        #expect(
            TabSelectionPolicy.tabForSceneActivation(
                isInitialActivation: false,
                initialTab: .usage,
                hasPendingHistoryLink: true) == .history)
    }

    @Test("Preview tab is limited to initial activation")
    func previewDoesNotRestoreAfterForegrounding() {
        #expect(
            TabSelectionPolicy.tabForSceneActivation(
                isInitialActivation: true,
                initialTab: .history,
                hasPendingHistoryLink: false) == .history)
        #expect(
            TabSelectionPolicy.tabForSceneActivation(
                isInitialActivation: false,
                initialTab: .history,
                hasPendingHistoryLink: false) == .usage)
    }
}
