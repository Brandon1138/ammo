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
            ?? states.first
        return UsageEntry(date: .now, state: state)
    }

    private func selectedAccountID(for configuration: SelectAccountIntent) -> UUID? {
        let states = SharedStore.load()
        return configuration.account
            .flatMap { chosen in states.first { $0.account.id == chosen.id }?.account.id }
            ?? states.first?.account.id
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

struct AllAccountsProvider: TimelineProvider {
    func placeholder(in context: Context) -> AllAccountsEntry {
        AmmoLog.widgetTimeline.debug("All Accounts placeholder requested")
        return AllAccountsEntry(date: .now, states: AccountState.galleryPlaceholders)
    }

    func getSnapshot(in context: Context, completion: @escaping (AllAccountsEntry) -> Void) {
        let entry = AllAccountsEntry(date: .now, states: SharedStore.load())
        AmmoLog.widgetTimeline.info("All Accounts snapshot produced with \(entry.states.count, privacy: .public) states")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AllAccountsEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let accountIDs = SharedStore.load().map(\.account.id)
            _ = await UsageRefreshCoordinator.shared.refresh(accountIDs: accountIDs,
                                                               reason: .widget)
            let states = SharedStore.load()
            let entry = AllAccountsEntry(date: .now, states: states)
            AmmoLog.widgetTimeline.info("All Accounts timeline produced with \(entry.states.count, privacy: .public) states")
            let entries = WidgetTimelineDates.make(states: states)
                .map { AllAccountsEntry(date: $0, states: states) }
            completion(Timeline(entries: entries,
                                policy: .after(RefreshLedgerStore.nextRefreshDate(states: states))))
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
}
