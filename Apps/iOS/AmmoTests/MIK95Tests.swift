import Foundation
import Testing
import UsageKit
import WidgetKit

@testable import Ammo

@MainActor
@Suite("MIK-95 all-providers board widget")
struct MIK95Tests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The board is offered in the tall iPhone family, never the iPad one")
    func boardFamilyIsPortraitExtraLarge() {
        let families = WidgetProviderPanels.accountsFamilies

        #expect(Array(families.prefix(3)) == [.systemSmall, .systemMedium, .systemLarge])
        // Ammo ships TARGETED_DEVICE_FAMILY = 1, so the landscape extra-large
        // family — iPad and Mac only — must never be declared.
        #expect(!families.contains(.systemExtraLarge))
        #expect(!WidgetProviderPanels.isProviderBoard(.systemLarge))
        #expect(!WidgetProviderPanels.isProviderBoard(.systemExtraLarge))

        if #available(iOS 27.0, *) {
            #expect(families == [.systemSmall, .systemMedium, .systemLarge,
                                 .systemExtraLargePortrait])
            #expect(WidgetProviderPanels.isProviderBoard(.systemExtraLargePortrait))
        } else {
            // Before the family existed there is nothing taller than large to
            // offer, and the board simply is not reachable.
            #expect(families.count == 3)
        }
    }

    @Test("A divider section preserves Claude's optional third window")
    func stackedPanelWindowBudget() {
        let resetsAt = now.addingTimeInterval(2 * 86_400)
        let snapshot = UsageSnapshot(
            provider: .claude,
            plan: nil,
            windows: [
                LimitWindow(kind: .session, label: "Session", usedPercent: 20,
                            resetsAt: now.addingTimeInterval(3_600)),
                LimitWindow(kind: .weekly, label: "Weekly", usedPercent: 40, resetsAt: resetsAt),
                LimitWindow(kind: .modelScoped, label: "Opus", usedPercent: 60, resetsAt: resetsAt),
            ],
            fetchedAt: now)

        #expect(WidgetProviderPanels.boardWindowLimit == 3)
        let groups = snapshot.widgetWindowGroups(limitedTo: WidgetProviderPanels.boardWindowLimit)
        #expect(groups.flatMap { $0 }.map(\.label) == ["Session", "Weekly", "Opus"])
        #expect(groups.map(\.count) == [1, 2])
    }

    @Test("The board keeps a fixed panel per shipping provider")
    func fixedPanelOrder() {
        let slots = WidgetProviderPanels.slots(states: [])

        #expect(slots.map(\.provider) == [.codex, .claude, .cursor, .openRouter])
        #expect(WidgetProviderPanels.providers.count == ProviderID.supported.count)
        #expect(Set(WidgetProviderPanels.providers) == Set(ProviderID.supported))
        #expect(slots.allSatisfy { $0.state == nil })
    }

    @Test("A provider without an account keeps its slot instead of collapsing")
    func missingProviderKeepsSlot() {
        let slots = WidgetProviderPanels.slots(states: [claudeState()])
        let claude = slots.first { $0.provider == .claude }
        let cursor = slots.first { $0.provider == .cursor }

        #expect(slots.count == 4)
        #expect(claude?.state?.account.provider == .claude)
        #expect(cursor?.state == nil)
    }

    @Test("Duplicate accounts resolve to the one with the most complete data")
    func duplicateProviderPicksRichestAccount() {
        var failing = claudeState(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
        failing.snapshot = nil
        failing.lastFailure = .authentication
        let slots = WidgetProviderPanels.slots(states: [failing, claudeState()])

        #expect(slots.first { $0.provider == .claude }?.state?.id == claudeState().id)
        #expect(slots.first { $0.provider == .claude }?.state?.snapshot != nil)
    }

    @Test("Every provider slot has display copy, never a blank panel")
    func slotsAlwaysHaveCopy() {
        var waiting = claudeState()
        waiting.snapshot = nil
        var failing = state(for: .codex)
        failing.snapshot = nil
        failing.lastFailure = .authentication

        let slots = WidgetProviderPanels.slots(states: [waiting, failing])

        // Every slot resolves to copy: a present state names its availability,
        // an absent one still names the provider the panel is asking for.
        for slot in slots {
            if let state = slot.state {
                #expect(!state.widgetAvailabilityText.isEmpty)
            } else {
                #expect(!slot.provider.displayName.isEmpty)
            }
        }

        #expect(slots.count == WidgetProviderPanels.providers.count)
        #expect(slots.filter { $0.state == nil }.map(\.provider) == [.cursor, .openRouter])
        #expect(slots.first { $0.provider == .claude }?.state?.widgetAvailabilityText
            == "No usage limits yet")
        #expect(slots.first { $0.provider == .codex }?.state?.widgetAvailabilityText
            == "Update paused — open Ammo")
    }

    @Test("An OpenRouter panel meters credits and labels its tier entitlement")
    func openRouterPanelContent() throws {
        let snapshot = UsageSnapshot(
            provider: .openRouter,
            plan: nil,
            windows: [],
            onDemand: [
                OnDemandUsage(
                    id: "openrouter-key-spending",
                    label: "API key spending",
                    kind: .spendingLimit,
                    scope: .personal,
                    isEnabled: true,
                    used: 25.5,
                    limit: 100,
                    remaining: 74.5,
                    periodStart: now.addingTimeInterval(-18 * 86_400),
                    resetsAt: now.addingTimeInterval(12 * 86_400)),
            ],
            isFreeTier: true,
            fetchedAt: now)
        let presentation = try #require(OpenRouterKeyPresentation(snapshot: snapshot))

        #expect(presentation.remainingFraction == 0.745)
        #expect(presentation.cadence == .monthly)
        #expect(presentation.tierBadge == "Free models: 50 req/day")
        // The widget must not invent a percentage window for money.
        #expect(snapshot.windows.isEmpty)
    }

    @Test("Truncated window lists keep their reset grouping")
    func windowGroupTruncation() {
        let resetsAt = now.addingTimeInterval(3 * 86_400)
        let snapshot = UsageSnapshot(
            provider: .claude,
            plan: nil,
            windows: [
                LimitWindow(kind: .session, label: "Session", usedPercent: 20,
                            resetsAt: now.addingTimeInterval(3_600)),
                LimitWindow(kind: .weekly, label: "Weekly", usedPercent: 40, resetsAt: resetsAt),
                LimitWindow(kind: .modelScoped, label: "Opus", usedPercent: 60, resetsAt: resetsAt),
                LimitWindow(kind: .modelScoped, label: "Fable", usedPercent: 80, resetsAt: resetsAt),
            ],
            fetchedAt: now)

        let groups = snapshot.windowGroups(limitedTo: 3)

        #expect(groups.map(\.count) == [1, 2])
        #expect(groups.flatMap { $0 }.map(\.label) == ["Session", "Weekly", "Opus"])
    }

    @Test("A fully configured board fills every panel")
    func fullyConfiguredBoard() {
        let states = WidgetProviderPanels.providers.enumerated().map { index, provider in
            AccountState(
                account: StoredAccount(provider: provider,
                                       label: provider.displayName),
                snapshot: UsageSnapshot(
                    provider: provider,
                    plan: nil,
                    windows: [
                        LimitWindow(kind: .weekly, label: "Weekly",
                                    usedPercent: Double(index * 10),
                                    resetsAt: now.addingTimeInterval(86_400)),
                    ],
                    fetchedAt: now),
                lastError: nil,
                updatedAt: now)
        }
        let slots = WidgetProviderPanels.slots(states: states.reversed())

        #expect(slots.allSatisfy { $0.state != nil })
        #expect(slots.map(\.provider) == WidgetProviderPanels.providers)
        #expect(slots.compactMap { $0.state?.account.provider } == slots.map(\.provider))
    }

    private func claudeState(
        id: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    ) -> AccountState {
        state(for: .claude, id: id)
    }

    private func state(
        for provider: ProviderID,
        id: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    ) -> AccountState {
        AccountState(
            account: StoredAccount(id: id, provider: provider, label: provider.displayName),
            snapshot: UsageSnapshot(
                provider: provider,
                plan: nil,
                windows: [
                    LimitWindow(kind: .session, label: "Session", usedPercent: 36,
                                resetsAt: now.addingTimeInterval(4 * 3_600)),
                ],
                fetchedAt: now),
            lastError: nil,
            updatedAt: now)
    }
}
