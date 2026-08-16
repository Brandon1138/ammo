import Foundation
import Testing
import UsageKit

@testable import Ammo

@MainActor
@Suite("MIK-92 OpenRouter integration")
struct MIK92Tests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("OpenRouter is the fourth shipping provider")
    func providerSelectorEnumeration() {
        #expect(ProviderID.supported == [.claude, .codex, .cursor, .openRouter])
        #expect(ProviderID.openRouter.displayName == "OpenRouter")
    }

    @Test("No-limit spending is amount-only, never remaining capacity")
    func amountOnlyPresentation() throws {
        let usage = openRouterUsage()
        let presentation = OnDemandUsagePresentation(
            usage: usage,
            referenceDate: now)

        #expect(presentation.primaryText.contains("23"))
        #expect(presentation.primaryText.hasSuffix(" used"))
        #expect(presentation.detailText == "No spending limit reported")
        #expect(presentation.statusText == "No limit")
        #expect(presentation.scopeText == "Personal")
        #expect(usage.remainingAmount == nil)
        #expect(usage.remainingFraction == nil)
    }

    @Test("App and widget account selectors retain OpenRouter identity")
    func selectorReachability() {
        let state = openRouterState()
        let ordered = WidgetAccountOrder.defaultOrder([state])

        #expect(ordered.map(\.id) == [state.id])
        #expect(ordered.first?.account.provider == .openRouter)
        #expect(ordered.first?.account.provider.displayName == "OpenRouter")
    }

    @Test("History keeps an amount-only account reachable")
    func historyReachability() {
        let state = openRouterState()
        let selection = HistorySelection(accountID: state.id)

        #expect(HistoryView.resolveState(in: [state], selection: selection)?.id == state.id)
        #expect(HistoryView.windowContent(for: state, selection: selection) == .noLimitWindows)
    }

    @Test("Widgets do not fabricate a percentage window for amount-only usage")
    func widgetWithoutPercentageWindow() {
        let state = openRouterState()
        let snapshot = state.snapshot!

        #expect(state.widgetPercentageWindow == nil)
        #expect(state.hasWidgetMeteredUsage)
        #expect(state.widgetAvailabilityText == "Metered usage only")
        #expect(state.widgetCompactAvailabilityText == "Metered")
        #expect(LockScreenUsagePresentation(snapshot: snapshot) == nil)
    }

    @Test("OpenRouter 429 uses the existing long backoff lane")
    func rateLimitBackoff() {
        #expect(RefreshFailureBackoff.delay(consecutiveFailures: 1, status: 429) == 5 * 60)
        #expect(RefreshFailureBackoff.delay(consecutiveFailures: 8, status: 429) == 60 * 60)
    }

    private func openRouterUsage() -> OnDemandUsage {
        OnDemandUsage(
            id: "openrouter-key-spending",
            label: "API key spending",
            kind: .spendingLimit,
            scope: .personal,
            isEnabled: true,
            isUnlimited: true,
            unit: .currency,
            dataSource: .providerUsageResponse,
            currencyCode: "USD",
            used: 23.75)
    }

    private func openRouterState() -> AccountState {
        let snapshot = UsageSnapshot(
            provider: .openRouter,
            plan: nil,
            windows: [],
            onDemand: [openRouterUsage()],
            fetchedAt: now)
        return AccountState(
            account: StoredAccount(
                id: UUID(uuidString: "92000000-0000-0000-0000-000000000092")!,
                provider: .openRouter,
                label: "OpenRouter",
                tokensImported: true),
            snapshot: snapshot,
            lastError: nil,
            lastFailure: nil,
            updatedAt: now)
    }
}
