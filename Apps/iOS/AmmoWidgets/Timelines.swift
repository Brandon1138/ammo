import Foundation
import UsageKit
import WidgetKit

// Widget timelines are cache-first and never wait on provider networking. The
// app and its background task own refreshes, commit snapshots to the App Group,
// then ask WidgetKit to reload. This lets a newly placed widget render the last
// successful snapshot immediately, even when WidgetKit limits network/runtime.
//
// Every provider entry point is instrumented. A widget stuck on its redacted
// placeholder is only diagnosable if the log distinguishes "WidgetKit never
// asked", "the provider was asked and read an empty cache", and "the provider
// was asked, read revision N, and returned entries" — so each phase logs the
// cache revision it saw, the number of entries it produced, and how long it
// took to produce them.

/// Emits one line per timeline-provider phase.
///
/// `phase` names the WidgetKit callback, `revision` identifies the App Group
/// write being rendered, and `newestSnapshot` is the timestamp any "Updated …
/// ago" text would reference — which makes an app-side "Saved rev=N" line and a
/// widget-side "read rev=N" line directly comparable.
enum WidgetTimelineDiagnostics {
    static func log(
        kind: String,
        phase: String,
        family: WidgetFamily?,
        stateCount: Int,
        entryCount: Int?,
        newestSnapshot: Date?,
        refreshDate: Date?,
        revision: SharedStoreRevision?,
        startedAt: Date
    ) {
        let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
        let formatter = ISO8601DateFormatter()
        let newest = newestSnapshot.map(formatter.string(from:)) ?? "none"
        let refresh = refreshDate.map(formatter.string(from:)) ?? "none"
        let revisionDescription = revision?.logDescription ?? "rev=unknown"
        AmmoLog.widgetTimeline.info(
            """
            \(kind, privacy: .public).\(phase, privacy: .public) \
            family=\(family.map(String.init(describing:)) ?? "unknown", privacy: .public) \
            states=\(stateCount, privacy: .public) \
            entries=\(entryCount.map(String.init) ?? "n/a", privacy: .public) \
            newestSnapshot=\(newest, privacy: .public) \
            nextRefresh=\(refresh, privacy: .public) \
            elapsed=\(elapsed, privacy: .public)ms \
            \(revisionDescription, privacy: .public)
            """)
    }

    static func newestSnapshot(in states: [AccountState]) -> Date? {
        states.compactMap(\.snapshot?.fetchedAt).max()
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let state: AccountState?
    let revision: SharedStoreRevision?
}

struct AccountTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        AmmoLog.widgetTimeline.debug("AmmoAccount.placeholder requested")
        return UsageEntry(date: .now, state: .placeholder, revision: nil)
    }

    func snapshot(for configuration: SelectAccountIntent, in context: Context) async -> UsageEntry {
        let startedAt = Date()
        let entry = entry(for: configuration)
        let states = entry.state.map { [$0] } ?? []
        WidgetTimelineDiagnostics.log(
            kind: "AmmoAccount", phase: "snapshot", family: context.family,
            stateCount: states.count, entryCount: 1,
            newestSnapshot: WidgetTimelineDiagnostics.newestSnapshot(in: states),
            refreshDate: nil, revision: entry.revision, startedAt: startedAt)
        return entry
    }

    func timeline(for configuration: SelectAccountIntent, in context: Context) async -> Timeline<UsageEntry> {
        let startedAt = Date()
        let entry = entry(for: configuration)
        let states = entry.state.map { [$0] } ?? []
        let refreshDate = RefreshLedgerStore.nextRefreshDate(states: states)
        let entries = timelineEntries(state: entry.state, revision: entry.revision)
        WidgetTimelineDiagnostics.log(
            kind: "AmmoAccount", phase: "timeline", family: context.family,
            stateCount: states.count, entryCount: entries.count,
            newestSnapshot: WidgetTimelineDiagnostics.newestSnapshot(in: states),
            refreshDate: refreshDate, revision: entry.revision, startedAt: startedAt)
        return Timeline(entries: entries, policy: .after(refreshDate))
    }

    private func entry(for configuration: SelectAccountIntent) -> UsageEntry {
        let snapshot = SharedStore.loadSnapshot()
        let state = configuration.account
            .flatMap { chosen in snapshot.states.first { $0.account.id == chosen.id } }
            ?? WidgetAccountOrder.defaultOrder(snapshot.states).first
        return UsageEntry(date: .now, state: state, revision: snapshot.revision)
    }

    private func timelineEntries(
        state: AccountState?,
        revision: SharedStoreRevision?
    ) -> [UsageEntry] {
        WidgetTimelineDates.make(states: state.map { [$0] } ?? [])
            .map { UsageEntry(date: $0, state: state, revision: revision) }
    }
}

struct AllAccountsEntry: TimelineEntry {
    let date: Date
    let states: [AccountState]
    let revision: SharedStoreRevision?
}

struct AllAccountsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AllAccountsEntry {
        AmmoLog.widgetTimeline.debug("All Accounts placeholder requested")
        // The board has a panel per provider, so its sample covers every
        // provider instead of the two the smaller families show.
        let states = WidgetProviderPanels.isProviderBoard(context.family)
            ? AccountState.providerBoardPlaceholders
            : AccountState.galleryPlaceholders
        return AllAccountsEntry(
            date: .now,
            states: WidgetAccountOrder.defaultOrder(states),
            revision: nil)
    }

    func snapshot(for configuration: SelectAccountsIntent, in context: Context) async -> AllAccountsEntry {
        let startedAt = Date()
        let entry = entry(for: configuration)
        // A gallery preview with nothing configured would otherwise show the
        // board as four empty panels, which reads as the layout rather than as
        // the person's own empty state.
        if context.isPreview, entry.states.isEmpty,
           WidgetProviderPanels.isProviderBoard(context.family) {
            return AllAccountsEntry(
                date: entry.date,
                states: WidgetAccountOrder.defaultOrder(AccountState.providerBoardPlaceholders),
                revision: entry.revision)
        }
        WidgetTimelineDiagnostics.log(
            kind: "AmmoAllAccounts", phase: "snapshot", family: context.family,
            stateCount: entry.states.count, entryCount: 1,
            newestSnapshot: WidgetTimelineDiagnostics.newestSnapshot(in: entry.states),
            refreshDate: nil, revision: entry.revision, startedAt: startedAt)
        return entry
    }

    func timeline(for configuration: SelectAccountsIntent, in context: Context) async -> Timeline<AllAccountsEntry> {
        let startedAt = Date()
        let entry = entry(for: configuration)
        let refreshDate = RefreshLedgerStore.nextRefreshDate(states: entry.states)
        let entries = WidgetTimelineDates.make(states: entry.states)
            .map { AllAccountsEntry(date: $0, states: entry.states, revision: entry.revision) }
        WidgetTimelineDiagnostics.log(
            kind: "AmmoAllAccounts", phase: "timeline", family: context.family,
            stateCount: entry.states.count, entryCount: entries.count,
            newestSnapshot: WidgetTimelineDiagnostics.newestSnapshot(in: entry.states),
            refreshDate: refreshDate, revision: entry.revision, startedAt: startedAt)
        return Timeline(entries: entries, policy: .after(refreshDate))
    }

    private func entry(for configuration: SelectAccountsIntent) -> AllAccountsEntry {
        let snapshot = SharedStore.loadSnapshot()
        let selectedIDs = configuration.orderedAccountIDs
        let visibleStates: [AccountState]
        if selectedIDs.isEmpty {
            visibleStates = WidgetAccountOrder.defaultOrder(snapshot.states)
        } else {
            visibleStates = selectedIDs.compactMap { id in
                snapshot.states.first { $0.id == id }
            }
        }
        return AllAccountsEntry(
            date: .now,
            states: visibleStates,
            revision: snapshot.revision)
    }
}

struct ActivityEntry: TimelineEntry {
    let date: Date
    let state: AccountState?
    let windowID: String?
    let samples: [UsageHistorySample]
    let revision: SharedStoreRevision?
}

struct ActivityTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ActivityEntry {
        let state = AccountState.placeholder
        let windowID = state.snapshot?.windows.first(where: { $0.kind == .weekly })?.id
        return ActivityEntry(
            date: .now,
            state: state,
            windowID: windowID,
            samples: Self.placeholderSamples(state: state, windowID: windowID),
            revision: nil
        )
    }

    func snapshot(for configuration: SelectLimitIntent, in context: Context) async -> ActivityEntry {
        let startedAt = Date()
        let entry = entry(for: configuration)
        let states = entry.state.map { [$0] } ?? []
        WidgetTimelineDiagnostics.log(
            kind: "AmmoActivity", phase: "snapshot", family: context.family,
            stateCount: states.count, entryCount: 1,
            newestSnapshot: WidgetTimelineDiagnostics.newestSnapshot(in: states),
            refreshDate: nil, revision: entry.revision, startedAt: startedAt)
        return entry
    }

    func timeline(for configuration: SelectLimitIntent, in context: Context) async -> Timeline<ActivityEntry> {
        let startedAt = Date()
        let entry = entry(for: configuration)
        let states = entry.state.map { [$0] } ?? []
        let refreshDate = RefreshLedgerStore.nextRefreshDate(states: states)
        let tomorrow = Calendar.current.nextDate(after: entry.date,
                                                 matching: DateComponents(hour: 0, minute: 0),
                                                 matchingPolicy: .nextTime) ?? refreshDate
        let policyDate = min(refreshDate, tomorrow)
        WidgetTimelineDiagnostics.log(
            kind: "AmmoActivity", phase: "timeline", family: context.family,
            stateCount: states.count, entryCount: 1,
            newestSnapshot: WidgetTimelineDiagnostics.newestSnapshot(in: states),
            refreshDate: policyDate, revision: entry.revision, startedAt: startedAt)
        return Timeline(entries: [entry], policy: .after(policyDate))
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
            samples: samples,
            revision: selection.revision
        )
    }

    private func selectedLimit(
        for configuration: SelectLimitIntent
    ) -> (state: AccountState?, windowID: String?, revision: SharedStoreRevision?) {
        let snapshot = SharedStore.loadSnapshot()
        if let chosen = configuration.limit,
           let state = snapshot.states.first(where: { $0.id == chosen.accountID }),
           state.snapshot?.windows.contains(where: { $0.id == chosen.windowID }) == true {
            return (state, chosen.windowID, snapshot.revision)
        }

        let orderedStates = WidgetAccountOrder.defaultOrder(snapshot.states)
        guard let state = orderedStates.first,
              let window = LimitQuery.preferredWindow(in: state.snapshot?.windows ?? []) else {
            return (orderedStates.first, nil, snapshot.revision)
        }
        return (state, window.id, snapshot.revision)
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
///
/// The schedule itself lives in `UsageKit.WidgetTimelinePlan` so it is bounded
/// and testable headless. The previous five-minute grid produced ~280 entries,
/// each carrying a full copy of every rendered account — an archive the widget
/// process has to build and WidgetKit has to accept before anything leaves the
/// placeholder, and the largest such archive belonged to the widest family.
enum WidgetTimelineDates {
    static func make(states: [AccountState], now: Date = .now) -> [Date] {
        WidgetTimelinePlan.dates(
            resetDates: states
                .compactMap(\.snapshot)
                .flatMap(\.windows)
                .compactMap(\.resetsAt),
            now: now)
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
                    LimitWindow(kind: .modelScoped, label: "Fable", usedPercent: 48,
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
        providerBoardPlaceholders(includesFable: true)
    }

    static var providerBoardPlaceholdersWithoutFable: [AccountState] {
        providerBoardPlaceholders(includesFable: false)
    }

    private static func providerBoardPlaceholders(includesFable: Bool) -> [AccountState] {
        let claudeWindows = [
            LimitWindow(kind: .session, label: "Session", usedPercent: 36,
                        resetsAt: Date(timeIntervalSinceNow: 4.5 * 3600)),
            LimitWindow(kind: .weekly, label: "Weekly", usedPercent: 12,
                        resetsAt: Date(timeIntervalSinceNow: 6.5 * 86400)),
        ] + (includesFable ? [
            LimitWindow(kind: .modelScoped, label: "Fable", usedPercent: 48,
                        resetsAt: Date(timeIntervalSinceNow: 6.5 * 86400)),
        ] : [])

        return [
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
            AccountState(
                account: StoredAccount(provider: .claude, label: "Claude"),
                snapshot: UsageSnapshot(
                    provider: .claude,
                    plan: "max",
                    windows: claudeWindows),
                lastError: nil,
                updatedAt: .now),
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
