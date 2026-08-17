import Foundation
import UsageKit
import WidgetKit

// Timeline requests use the same provider-neutral coordinator as the app. The
// coordinator serves a cache hit inside the 60-second floor and owns the network
// fetch otherwise, so opening Ammo and a WidgetKit wake cannot double-request.

struct UsageEntry: TimelineEntry {
    let date: Date
    let state: AccountState?
}

struct AccountTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        AmmoLog.widgetTimeline.debug("Account placeholder requested")
        return UsageEntry(date: .now, state: .placeholder)
    }

    func snapshot(for configuration: SelectAccountIntent, in context: Context) async -> UsageEntry {
        let entry = entry(for: configuration)
        AmmoLog.widgetTimeline.info("Account snapshot produced; hasState=\(entry.state != nil, privacy: .public)")
        return entry
    }

    func timeline(for configuration: SelectAccountIntent, in context: Context) async -> Timeline<UsageEntry> {
        if let accountID = selectedAccountID(for: configuration) {
            _ = await UsageRefreshCoordinator.shared.refresh(accountID: accountID,
                                                               reason: .widget)
        }
        let entry = entry(for: configuration)
        AmmoLog.widgetTimeline.info("Account timeline produced; hasState=\(entry.state != nil, privacy: .public)")
        let states = entry.state.map { [$0] } ?? []
        return Timeline(entries: timelineEntries(state: entry.state),
                        policy: .after(RefreshLedgerStore.nextRefreshDate(states: states)))
    }

    private func entry(for configuration: SelectAccountIntent) -> UsageEntry {
        let states = SharedStore.load()
        let state = configuration.account
            .flatMap { chosen in states.first { $0.account.id == chosen.id } }
            ?? WidgetAccountOrder.defaultOrder(states).first
        return UsageEntry(date: .now, state: state)
    }

    private func selectedAccountID(for configuration: SelectAccountIntent) -> UUID? {
        let states = SharedStore.load()
        return configuration.account
            .flatMap { chosen in states.first { $0.account.id == chosen.id }?.account.id }
            ?? WidgetAccountOrder.defaultOrder(states).first?.account.id
    }


    private func timelineEntries(state: AccountState?) -> [UsageEntry] {
        WidgetTimelineDates.make(states: state.map { [$0] } ?? [])
            .map { UsageEntry(date: $0, state: state) }
    }
}

struct AllAccountsEntry: TimelineEntry {
    let date: Date
    let states: [AccountState]
}

struct AllAccountsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AllAccountsEntry {
        AmmoLog.widgetTimeline.debug("All Accounts placeholder requested")
        // The extra-large board has a panel per provider, so its sample covers
        // every provider instead of the two the smaller families show.
        let states = context.family == .systemExtraLarge
            ? AccountState.providerBoardPlaceholders
            : AccountState.galleryPlaceholders
        return AllAccountsEntry(
            date: .now,
            states: WidgetAccountOrder.defaultOrder(states))
    }

    func snapshot(for configuration: SelectAccountsIntent, in context: Context) async -> AllAccountsEntry {
        let entry = entry(for: configuration)
        // A gallery preview with nothing configured would otherwise show the
        // extra-large board as four empty panels, which reads as the layout
        // rather than as the person's own empty state.
        if context.isPreview, entry.states.isEmpty, context.family == .systemExtraLarge {
            return AllAccountsEntry(
                date: entry.date,
                states: WidgetAccountOrder.defaultOrder(AccountState.providerBoardPlaceholders))
        }
        AmmoLog.widgetTimeline.info("All Accounts snapshot produced with \(entry.states.count, privacy: .public) states")
        return entry
    }

    func timeline(for configuration: SelectAccountsIntent, in context: Context) async -> Timeline<AllAccountsEntry> {
        let allStates = SharedStore.load()
        let selectedIDs = configuration.orderedAccountIDs
        let refreshIDs = selectedIDs.isEmpty ? allStates.map(\.id) : selectedIDs
        _ = await UsageRefreshCoordinator.shared.refresh(accountIDs: refreshIDs, reason: .widget)

        let entry = entry(for: configuration)
        AmmoLog.widgetTimeline.info("All Accounts timeline produced with \(entry.states.count, privacy: .public) states")
        let entries = WidgetTimelineDates.make(states: entry.states)
            .map { AllAccountsEntry(date: $0, states: entry.states) }
        return Timeline(
            entries: entries,
            policy: .after(RefreshLedgerStore.nextRefreshDate(states: entry.states)))
    }

    private func entry(for configuration: SelectAccountsIntent) -> AllAccountsEntry {
        let states = SharedStore.load()
        let selectedIDs = configuration.orderedAccountIDs
        let visibleStates: [AccountState]
        if selectedIDs.isEmpty {
            visibleStates = WidgetAccountOrder.defaultOrder(states)
        } else {
            visibleStates = selectedIDs.compactMap { id in
                states.first { $0.id == id }
            }
        }
        return AllAccountsEntry(date: .now, states: visibleStates)
    }
}

struct ActivityEntry: TimelineEntry {
    let date: Date
    let state: AccountState?
    let windowID: String?
    let samples: [UsageHistorySample]
}

struct ActivityTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ActivityEntry {
        let state = AccountState.placeholder
        let windowID = state.snapshot?.windows.first(where: { $0.kind == .weekly })?.id
        return ActivityEntry(
            date: .now,
            state: state,
            windowID: windowID,
            samples: Self.placeholderSamples(state: state, windowID: windowID)
        )
    }

    func snapshot(for configuration: SelectLimitIntent, in context: Context) async -> ActivityEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectLimitIntent, in context: Context) async -> Timeline<ActivityEntry> {
        let initial = selectedLimit(for: configuration)
        if let accountID = initial.state?.id {
            _ = await UsageRefreshCoordinator.shared.refresh(accountID: accountID, reason: .widget)
        }

        let entry = entry(for: configuration)
        let states = entry.state.map { [$0] } ?? []
        let refreshDate = RefreshLedgerStore.nextRefreshDate(states: states)
        let tomorrow = Calendar.current.nextDate(after: entry.date,
                                                 matching: DateComponents(hour: 0, minute: 0),
                                                 matchingPolicy: .nextTime) ?? refreshDate
        return Timeline(entries: [entry], policy: .after(min(refreshDate, tomorrow)))
    }

    private func entry(for configuration: SelectLimitIntent) -> ActivityEntry {
        let selection = selectedLimit(for: configuration)
        let samples = selection.state.map { state in
            UsageHistoryStore.load().filter { $0.accountID == state.id }
        } ?? []
        return ActivityEntry(
            date: .now,
            state: selection.state,
            windowID: selection.windowID,
            samples: samples
        )
    }

    private func selectedLimit(for configuration: SelectLimitIntent) -> (state: AccountState?, windowID: String?) {
        let states = SharedStore.load()
        if let chosen = configuration.limit,
           let state = states.first(where: { $0.id == chosen.accountID }),
           state.snapshot?.windows.contains(where: { $0.id == chosen.windowID }) == true {
            return (state, chosen.windowID)
        }

        let orderedStates = WidgetAccountOrder.defaultOrder(states)
        guard let state = orderedStates.first,
              let window = LimitQuery.preferredWindow(in: state.snapshot?.windows ?? []) else {
            return (orderedStates.first, nil)
        }
        return (state, window.id)
    }

    private static func placeholderSamples(state: AccountState, windowID: String?) -> [UsageHistorySample] {
        guard let base = state.snapshot,
              let windowID,
              let window = base.windows.first(where: { $0.id == windowID }) else { return [] }

        return (0..<22).map { offset in
            let date = Date().addingTimeInterval(TimeInterval(-(22 - offset)) * 24 * 60 * 60)
            let used = Double((offset * 7) % 48)
            return UsageHistorySample(
                accountID: state.id,
                snapshot: UsageSnapshot(
                    provider: base.provider,
                    plan: base.plan,
                    windows: [
                        LimitWindow(kind: window.kind,
                                    label: window.label,
                                    usedPercent: used,
                                    resetsAt: window.resetsAt),
                    ],
                    fetchedAt: date
                )
            )
        }
    }
}


/// Preloads local-only display updates far enough to keep week-long countdowns
/// moving even when WidgetKit defers network/timeline reloads. Exact reset
/// boundaries switch stale meters to the conservative "Reset due" state.
private enum WidgetTimelineDates {
    static func make(states: [AccountState], now: Date = .now) -> [Date] {
        var dates = [now]

        let fineEnd = now.addingTimeInterval(2 * 3600)
        var next = now.addingTimeInterval(5 * 60)
        while next <= fineEnd {
            dates.append(next)
            next = next.addingTimeInterval(5 * 60)
        }

        let dayEnd = now.addingTimeInterval(24 * 3600)
        next = fineEnd.addingTimeInterval(15 * 60)
        while next <= dayEnd {
            dates.append(next)
            next = next.addingTimeInterval(15 * 60)
        }

        let horizon = now.addingTimeInterval(8 * 24 * 3600)
        next = dayEnd.addingTimeInterval(60 * 60)
        while next <= horizon {
            dates.append(next)
            next = next.addingTimeInterval(60 * 60)
        }

        let resetDates = states
            .compactMap(\.snapshot)
            .flatMap(\.windows)
            .compactMap(\.resetsAt)
            .filter { $0 > now && $0 <= horizon }
        dates.append(contentsOf: resetDates)
        return Array(Set(dates)).sorted()
    }
}

extension AccountState {
    /// Redacted-looking sample for placeholders and the widget gallery.
    static var placeholder: AccountState {
        AccountState(
            account: StoredAccount(provider: .claude, label: "Claude"),
            snapshot: UsageSnapshot(
                provider: .claude,
                plan: nil,
                windows: [
                    LimitWindow(kind: .session, label: "Session", usedPercent: 36,
                                resetsAt: Date(timeIntervalSinceNow: 4.5 * 3600)),
                    LimitWindow(kind: .weekly, label: "Weekly", usedPercent: 12,
                                resetsAt: Date(timeIntervalSinceNow: 6.5 * 86400)),
                ]),
            lastError: nil,
            updatedAt: .now)
    }

    /// Multi-provider sample so the gallery shows the real layout.
    static var galleryPlaceholders: [AccountState] {
        [
            AccountState(
                account: StoredAccount(provider: .codex, label: "Codex"),
                snapshot: UsageSnapshot(
                    provider: .codex,
                    plan: nil,
                    windows: [
                        LimitWindow(kind: .weekly, label: "Weekly", usedPercent: 30,
                                    resetsAt: Date(timeIntervalSinceNow: 5.9 * 86400)),
                    ]),
                lastError: nil,
                updatedAt: .now),
            .placeholder,
        ]
    }

    /// One sample account per shipping provider for the extra-large board, in
    /// each provider's own shape: percentage windows for Codex, Claude, and
    /// Cursor, and amount-only key spending for OpenRouter.
    static var providerBoardPlaceholders: [AccountState] {
        galleryPlaceholders + [
            AccountState(
                account: StoredAccount(provider: .cursor, label: "Cursor"),
                snapshot: UsageSnapshot(
                    provider: .cursor,
                    plan: nil,
                    windows: [
                        LimitWindow(kind: .monthly, label: "Composer", usedPercent: 54,
                                    resetsAt: Date(timeIntervalSinceNow: 11 * 86400)),
                        LimitWindow(kind: .monthly, label: "API", usedPercent: 18,
                                    resetsAt: Date(timeIntervalSinceNow: 11 * 86400)),
                    ]),
                lastError: nil,
                updatedAt: .now),
            AccountState(
                account: StoredAccount(provider: .openRouter, label: "OpenRouter"),
                snapshot: UsageSnapshot(
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
                            periodStart: Date(timeIntervalSinceNow: -18 * 86400),
                            resetsAt: Date(timeIntervalSinceNow: 12 * 86400)),
                    ],
                    isFreeTier: false),
                lastError: nil,
                updatedAt: .now),
        ]
    }
}
