import UsageKit
import WidgetKit

// Timelines are cheap: one entry rendered from the App Group cache, refreshed
// ~every 30 minutes (WidgetKit budgets ~40–70 reloads/day). Reset countdowns
// stay live between reloads via Text(_:style:.relative). The app also forces a
// reload after every fetch, so entries rarely go stale in practice.

struct UsageEntry: TimelineEntry {
    let date: Date
    let state: AccountState?
}

struct AccountTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, state: .placeholder)
    }

    func snapshot(for configuration: SelectAccountIntent, in context: Context) async -> UsageEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectAccountIntent, in context: Context) async -> Timeline<UsageEntry> {
        Timeline(entries: [entry(for: configuration)],
                 policy: .after(Date(timeIntervalSinceNow: 30 * 60)))
    }

    private func entry(for configuration: SelectAccountIntent) -> UsageEntry {
        let states = SharedStore.load()
        let state = configuration.account
            .flatMap { chosen in states.first { $0.account.id == chosen.id } }
            ?? states.first
        return UsageEntry(date: .now, state: state)
    }
}

struct AllAccountsEntry: TimelineEntry {
    let date: Date
    let states: [AccountState]
}

struct AllAccountsProvider: TimelineProvider {
    func placeholder(in context: Context) -> AllAccountsEntry {
        AllAccountsEntry(date: .now, states: [.placeholder])
    }

    func getSnapshot(in context: Context, completion: @escaping (AllAccountsEntry) -> Void) {
        completion(AllAccountsEntry(date: .now, states: SharedStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AllAccountsEntry>) -> Void) {
        let entry = AllAccountsEntry(date: .now, states: SharedStore.load())
        completion(Timeline(entries: [entry],
                            policy: .after(Date(timeIntervalSinceNow: 30 * 60))))
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
                                resetsAt: Date(timeIntervalSinceNow: 2 * 3600)),
                    LimitWindow(kind: .weekly, label: "Weekly", usedPercent: 12,
                                resetsAt: Date(timeIntervalSinceNow: 3 * 86400)),
                ]),
            lastError: nil,
            updatedAt: .now)
    }
}
