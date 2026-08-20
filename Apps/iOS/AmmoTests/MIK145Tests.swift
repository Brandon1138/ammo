import Foundation
import Testing
import UsageKit

@testable import Ammo

@MainActor
@Suite("MIK-145 Codex Spark metering")
struct MIK145Tests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func codexSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex,
            plan: nil,
            windows: [
                LimitWindow(kind: .weekly, label: "Weekly", usedPercent: 100,
                            resetsAt: now.addingTimeInterval(4.8 * 86_400)),
                LimitWindow(kind: .modelScoped, label: "Spark session", usedPercent: 12,
                            resetsAt: now.addingTimeInterval(3 * 3_600)),
                LimitWindow(kind: .modelScoped, label: "Spark weekly", usedPercent: 34,
                            resetsAt: now.addingTimeInterval(6.9 * 86_400)),
            ],
            fetchedAt: now)
    }

    private func codexState() -> AccountState {
        AccountState(account: StoredAccount(provider: .codex, label: "Codex"),
                     snapshot: codexSnapshot(),
                     lastError: nil,
                     lastFailure: nil,
                     updatedAt: now)
    }

    // MARK: - Toggle store

    @Test("The preference persists to the App Group and defaults to off")
    func togglePersists() throws {
        let original = UsageDisplayPreferences.showsCodexSpark
        defer { try? UsageDisplayPreferences.setShowsCodexSpark(original) }

        try UsageDisplayPreferences.setShowsCodexSpark(false)
        #expect(!UsageDisplayPreferences.showsCodexSpark)

        try UsageDisplayPreferences.setShowsCodexSpark(true)
        #expect(UsageDisplayPreferences.showsCodexSpark)
        // Setting the same value twice must stay idempotent, not throw on the
        // marker file already existing.
        try UsageDisplayPreferences.setShowsCodexSpark(true)
        #expect(UsageDisplayPreferences.showsCodexSpark)

        try UsageDisplayPreferences.setShowsCodexSpark(false)
        #expect(!UsageDisplayPreferences.showsCodexSpark)
        try UsageDisplayPreferences.setShowsCodexSpark(false)
        #expect(!UsageDisplayPreferences.showsCodexSpark)
    }

    // MARK: - Presentation filter

    @Test("Spark windows are matched by label only under the model-scoped kind")
    func sparkWindowIdentification() {
        #expect(LimitWindow(kind: .modelScoped, label: "Spark session", usedPercent: 0,
                            resetsAt: nil).isCodexSparkWindow)
        // Snapshots cached before the rename still carry the bare label.
        #expect(LimitWindow(kind: .modelScoped, label: "Spark", usedPercent: 0,
                            resetsAt: nil).isCodexSparkWindow)
        #expect(LimitWindow(kind: .modelScoped, label: "Spark weekly", usedPercent: 0,
                            resetsAt: nil).isCodexSparkWindow)
        #expect(!LimitWindow(kind: .modelScoped, label: "Fable", usedPercent: 0,
                             resetsAt: nil).isCodexSparkWindow)
        #expect(!LimitWindow(kind: .weekly, label: "Spark", usedPercent: 0,
                             resetsAt: nil).isCodexSparkWindow)
    }

    @Test("Presentation hides Spark when off and keeps every other field intact")
    func filterHidesSparkWithoutTouchingTheRest() {
        let snapshot = codexSnapshot()

        let shown = UsageDisplayPreferences.presented(snapshot, showingCodexSpark: true)
        #expect(shown.windows.map(\.label) == ["Weekly", "Spark session", "Spark weekly"])

        let hidden = UsageDisplayPreferences.presented(snapshot, showingCodexSpark: false)
        #expect(hidden.windows.map(\.label) == ["Weekly"])
        #expect(hidden.plan == snapshot.plan)
        #expect(hidden.onDemand == snapshot.onDemand)
        #expect(hidden.fetchedAt == snapshot.fetchedAt)
        // Ingestion is untouched: the source snapshot still carries the meters,
        // so flipping the preference back needs no refetch.
        #expect(snapshot.windows.count == 3)
    }

    @Test("Filtering leaves other providers' model buckets alone")
    func filterSparesFable() {
        let claude = UsageSnapshot(
            provider: .claude,
            plan: "max",
            windows: [
                LimitWindow(kind: .session, label: "Session", usedPercent: 20, resetsAt: nil),
                LimitWindow(kind: .modelScoped, label: "Fable", usedPercent: 48, resetsAt: nil),
            ],
            fetchedAt: now)
        let state = AccountState(account: StoredAccount(provider: .claude, label: "Claude"),
                                 snapshot: claude, lastError: nil, lastFailure: nil,
                                 updatedAt: now)

        let filtered = UsageDisplayPreferences.presented([state], showingCodexSpark: false)
        #expect(filtered[0].snapshot?.windows.map(\.label) == ["Session", "Fable"])
    }

    // MARK: - Board composition

    @Test("Off keeps the existing four-provider board")
    func boardWithSparkOff() {
        #expect(WidgetProviderPanels.providers(showingCodexSpark: false)
            == [.codex, .claude, .cursor, .openRouter])

        let slots = WidgetProviderPanels.slots(states: [codexState()], showingCodexSpark: false)
        #expect(slots.map(\.provider) == [.codex, .claude, .cursor, .openRouter])
        #expect(slots.count == ProviderID.supported.count)
    }

    @Test("On drops OpenRouter so Codex can expand")
    func boardWithSparkOn() {
        #expect(WidgetProviderPanels.providers(showingCodexSpark: true)
            == [.codex, .claude, .cursor])

        let slots = WidgetProviderPanels.slots(states: [codexState()], showingCodexSpark: true)
        #expect(slots.map(\.provider) == [.codex, .claude, .cursor])
        #expect(!slots.contains { $0.provider == .openRouter })
        #expect(slots.first?.state?.snapshot?.windows.count == 3)
    }

    @Test("The board's window budget fits Codex's weekly window plus both Spark meters")
    func expandedCodexFitsTheSlotBudget() {
        let groups = codexSnapshot()
            .widgetWindowGroups(limitedTo: WidgetProviderPanels.boardWindowLimit)

        #expect(groups.flatMap { $0 }.map(\.label) == ["Weekly", "Spark session", "Spark weekly"])
        // Three distinct reset moments, so no two meters share a footer.
        #expect(groups.map(\.count) == [1, 1, 1])
    }

    @Test("In-app rows render Spark through the ordinary multi-window grouping")
    func accountRowsUseTheSharedWindowGrouping() {
        #expect(codexSnapshot().windowGroups.flatMap { $0 }.map(\.label)
            == ["Weekly", "Spark session", "Spark weekly"])
        let hidden = UsageDisplayPreferences.presented(codexSnapshot(), showingCodexSpark: false)
        #expect(hidden.windowGroups.flatMap { $0 }.map(\.label) == ["Weekly"])
    }
}
