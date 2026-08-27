import Charts
import SwiftUI
import UsageKit

struct HistorySelection: Equatable {
    var accountID: UUID?
    var windowID: String?
}

/// What History can honestly render *beneath* the account selector. The selector
/// itself is unconditional chrome, so an account with no chartable window keeps
/// account and provider switching instead of collapsing into a dead end.
enum HistoryWindowContent: Equatable {
    /// A limit window exists and is selected. Samples may still be too sparse.
    case window(String)
    /// A snapshot was accepted but the provider reported no limit windows —
    /// usage-based plans (Codex Business, for example) look like this.
    case noLimitWindows
    /// Nothing has been fetched for this account yet, or the last fetch failed
    /// before any snapshot was stored.
    case awaitingSnapshot

    var windowID: String? {
        guard case .window(let id) = self else { return nil }
        return id
    }
}

struct HistoryView: View {
    @Environment(AccountStore.self) private var store
    @Binding var selection: HistorySelection
    @State private var range: HistoryRange = .week
    @State private var selectedTrendDate: Date?
    @State private var presentedSheet: AmmoTabSheet?

    var body: some View {
        NavigationStack {
            Group {
                if let state = selectedState {
                    historyContent(state: state)
                } else {
                    ContentUnavailableView {
                        Label("No accounts yet", systemImage: "chart.xyaxis.line")
                    } description: {
                        Text("Add an account from Usage to begin collecting history.")
                    }
                }
            }
            .ammoTabHeader(sheet: $presentedSheet)
            .onAppear {
                store.reloadHistory()
                normalizeSelection()
            }
            .onChange(of: store.states.map(\.id)) { _, _ in
                normalizeSelection()
            }
        }
    }

    private func historyContent(state: AccountState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AccountHistorySelector(
                    states: store.states,
                    selected: state,
                    select: selectAccount
                )

                switch Self.windowContent(for: state, selection: selection) {
                case .window(let windowID):
                    chartSections(state: state, windowID: windowID)
                case .noLimitWindows:
                    unavailableSection(
                        title: "No limits to chart",
                        systemImage: "chart.xyaxis.line",
                        message: "\(state.account.provider.displayName) reports no usage limit window for this account, so Ammo has no allowance to trend over time.")
                case .awaitingSnapshot:
                    unavailableSection(
                        title: "No usage data yet",
                        systemImage: "arrow.clockwise",
                        message: "Pull down to refresh \(state.account.label). History begins once Ammo has an update to record.")
                }

                if let failure = state.activeFailure {
                    RefreshIssueNotice(
                        providerName: state.account.provider.displayName,
                        failure: failure,
                        hasCachedSnapshot: state.snapshot != nil,
                        retryState: store.retryState(for: state.id, at: .now),
                        retry: {
                            Task { await store.refresh(ids: [state.id], reason: .manual) }
                        },
                        reconnect: { presentedSheet = .reconnect(state.account) })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .refreshable {
            await store.refresh(ids: [state.id], reason: .manual)
        }
    }

    @ViewBuilder
    private func chartSections(state: AccountState, windowID: String) -> some View {
        let windows = state.snapshot?.windows ?? []
        if let window = windows.first(where: { $0.id == windowID }) {
            if windows.count > 1 {
                Picker("Limit", selection: windowBinding(fallback: window.id)) {
                    ForEach(windows) { candidate in
                        Text(candidate.label).tag(candidate.id)
                    }
                }
                .pickerStyle(.segmented)
            }

            if hasSamples(for: state.id, windowID: window.id) {
                ActivityHistorySection(
                    days: activityDays(for: state.id, windowID: window.id)
                )

                Divider()

                RemainingTrendSection(
                    points: trendPoints(for: state.id, windowID: window.id),
                    range: $range,
                    selectedDate: $selectedTrendDate
                )
            } else {
                unavailableSection(
                    title: "History starts here",
                    systemImage: "square.grid.3x3.fill",
                    message: "Ammo will build this view as it observes changes to \(window.label.lowercased()) usage on this device.")
            }
        }
    }

    private func unavailableSection(
        title: String,
        systemImage: String,
        message: String
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private var selectedState: AccountState? {
        Self.resolveState(in: store.states, selection: selection)
    }

    /// Resolves the selected account, falling back to the first account only when
    /// the selected id no longer exists. Never returns nil while any account does.
    static func resolveState(
        in states: [AccountState],
        selection: HistorySelection
    ) -> AccountState? {
        if let accountID = selection.accountID,
           let state = states.first(where: { $0.id == accountID }) {
            return state
        }
        return states.first
    }

    static func windowContent(
        for state: AccountState,
        selection: HistorySelection
    ) -> HistoryWindowContent {
        guard let snapshot = state.snapshot else { return .awaitingSnapshot }
        let windows = snapshot.windows
        if let windowID = selection.windowID,
           windows.contains(where: { $0.id == windowID }) {
            return .window(windowID)
        }
        guard let preferred = preferredWindow(in: windows) else { return .noLimitWindows }
        return .window(preferred.id)
    }

    static func preferredWindow(in windows: [LimitWindow]) -> LimitWindow? {
        windows.first(where: { $0.kind == .weekly })
            ?? windows.first(where: { $0.kind == .monthly })
            ?? windows.first
    }

    private func normalizeSelection() {
        guard let state = selectedState else {
            selection = HistorySelection()
            return
        }
        let normalized = HistorySelection(
            accountID: state.id,
            windowID: Self.windowContent(for: state, selection: selection).windowID)
        if selection != normalized { selection = normalized }
    }

    private func selectAccount(_ id: UUID) {
        guard let state = store.states.first(where: { $0.id == id }) else { return }
        selection.accountID = id
        selection.windowID = Self.preferredWindow(in: state.snapshot?.windows ?? [])?.id
        selectedTrendDate = nil
    }

    private func windowBinding(fallback: String) -> Binding<String> {
        Binding(
            get: { selection.windowID ?? fallback },
            set: {
                selection.windowID = $0
                selectedTrendDate = nil
            }
        )
    }

    private func hasSamples(for accountID: UUID, windowID: String) -> Bool {
        store.historySamples.lazy.filter {
            $0.accountID == accountID && $0.snapshot.windows.contains(where: { $0.id == windowID })
        }.prefix(2).count == 2
    }

    private func activityDays(for accountID: UUID, windowID: String) -> [UsageActivityDay] {
        UsageHistoryAnalysis.activityDays(
            samples: store.historySamples,
            accountID: accountID,
            windowID: windowID,
            endingAt: .now,
            weekCount: 12
        )
    }

    private func trendPoints(for accountID: UUID, windowID: String) -> [UsageTrendPoint] {
        UsageHistoryAnalysis.trendPoints(
            samples: store.historySamples,
            accountID: accountID,
            windowID: windowID,
            since: Date().addingTimeInterval(-range.duration)
        )
    }
}

/// Takes the resolved account rather than an id so the label can never render
/// empty — an empty label would leave the History screen with no way out.
private struct AccountHistorySelector: View {
    let states: [AccountState]
    let selected: AccountState
    let select: (UUID) -> Void

    var body: some View {
        Menu {
            ForEach(states) { state in
                Button {
                    select(state.id)
                } label: {
                    Label(state.account.label,
                          systemImage: state.id == selected.id ? "checkmark" : "circle")
                }
            }
        } label: {
            HStack(spacing: 8) {
                ProviderLogo(provider: selected.account.provider, size: 22)
                Text(selected.account.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ActivityHistorySection: View {
    let days: [UsageActivityDay]

    private var activeDays: Int { days.filter(\.isActive).count }
    private var observedUse: Int {
        Int(days.reduce(0) { $0 + $1.observedUsedPercent }.rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Activity")
                    .font(.headline)
                Spacer()
                Text("12 weeks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ActivityHeatmap(days: days, spacing: 4, cornerRadius: 3)
                .frame(maxWidth: .infinity)

            HStack {
                Text("\(activeDays) active day\(activeDays == 1 ? "" : "s")")
                Spacer()
                Text("\(observedUse) pts used")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// Repairs an expired provider session under the same account id, mirroring
/// the account menu's "Sign In Again" on Usage — history stays attached.
private enum HistoryRange: String, CaseIterable, Identifiable {
    case day = "24H"
    case week = "7D"
    case month = "30D"

    var id: Self { self }

    var duration: TimeInterval {
        switch self {
        case .day: 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        case .month: 30 * 24 * 60 * 60
        }
    }
}

private struct SegmentedTrendPoint: Identifiable {
    let point: UsageTrendPoint
    let segment: Int

    var id: Date { point.id }
}

private struct RemainingTrendSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let points: [UsageTrendPoint]
    @Binding var range: HistoryRange
    @Binding var selectedDate: Date?

    private var selectedPoint: UsageTrendPoint? {
        guard let selectedDate else { return points.last }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private var segmentedPoints: [SegmentedTrendPoint] {
        let threshold = range.duration / 10
        var segment = 0
        var previousDate: Date?
        return points.map { point in
            if let previousDate, point.date.timeIntervalSince(previousDate) > threshold {
                segment += 1
            }
            previousDate = point.date
            return SegmentedTrendPoint(point: point, segment: segment)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            trendHeader

            if points.isEmpty {
                Text("No observations in this range.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart {
                    ForEach(segmentedPoints) { item in
                        LineMark(
                            x: .value("Time", item.point.date),
                            y: .value("Remaining", item.point.remainingPercent),
                            series: .value("Segment", item.segment)
                        )
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(.blue)

                        PointMark(
                            x: .value("Observation", item.point.date),
                            y: .value("Remaining", item.point.remainingPercent)
                        )
                        .symbolSize(14)
                        .foregroundStyle(.blue)

                        if item.point.resetOccurred {
                            RuleMark(x: .value("Reset", item.point.date))
                                .foregroundStyle(.secondary.opacity(0.45))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100])
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .chartXSelection(value: $selectedDate)
                .frame(height: 190)
                .accessibilityLabel("Remaining allowance over time")
            }

            Text("Lines break where Ammo has no observations. Reset markers show confirmed provider rollovers.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trendHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                remainingSummary
                rangePicker
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                remainingSummary
                Spacer()
                rangePicker
            }
        }
    }

    private var remainingSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Remaining")
                .font(.headline)
            if let selectedPoint {
                Text("\(Int(selectedPoint.remainingPercent.rounded()))%")
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(HistoryRange.allCases) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 190)
    }
}
