import SwiftUI
import UsageKit
import WidgetKit

// MARK: - Single account (systemSmall + accessoryCircular)

struct AccountWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    init(entry: UsageEntry) {
        self.entry = entry
        AmmoLog.widgetRender.debug("Constructing Account widget; hasState=\(entry.state != nil, privacy: .public)")
    }

    var body: some View {
        if let state = entry.state {
            switch family {
            case .accessoryCircular:
                CircularGaugeView(state: state)
            default:
                SmallAccountView(state: state, referenceDate: entry.date)
            }
        } else {
            SetupHintView()
        }
    }
}

struct SetupHintView: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "battery.0percent")
            Text("Set up in Ammo")
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - Activity (systemSmall + systemMedium)

struct ActivityWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ActivityEntry

    private var weekCount: Int {
        family == .systemMedium ? 17 : 7
    }

    var body: some View {
        if let state = entry.state,
           let windowID = entry.windowID,
           let window = state.snapshot?.windows.first(where: { $0.id == windowID }) {
            graph(
                days: UsageHistoryAnalysis.activityDays(
                    samples: entry.samples,
                    accountID: state.id,
                    windowID: window.id,
                    endingAt: entry.date,
                    weekCount: weekCount
                )
            )
            .widgetURL(HistoryLink(accountID: state.id, windowID: window.id).url)
        } else {
            graph(days: emptyDays)
        }
    }

    private var emptyDays: [UsageActivityDay] {
        UsageHistoryAnalysis.activityDays(
            samples: [],
            accountID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            windowID: "",
            endingAt: entry.date,
            weekCount: weekCount
        )
    }

    private func graph(days: [UsageActivityDay]) -> some View {
        ActivityHeatmap(
            days: days,
            spacing: 4,
            cornerRadius: 2,
            matchesContainerCorners: true
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// systemSmall: logo + bold name header, then up to two windows as
/// label / percent / thick bar / reset countdown.
struct SmallAccountView: View {
    let state: AccountState
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ProviderLogo(provider: state.account.provider, size: 20)
                Text(state.account.label)
                    .font(.headline)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 0)
            }
            if let snapshot = state.snapshot, !snapshot.windows.isEmpty {
                ForEach(compactGroups(snapshot), id: \.first!.id) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(group) { window in
                            UsageWindowRow(window: window,
                                           font: .subheadline,
                                           barHeight: 7,
                                           spacing: 2)
                        }
                        ResetStatusLine(snapshot: snapshot,
                                        group: group,
                                        referenceDate: referenceDate,
                                        font: .footnote)
                    }
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text(state.widgetAvailabilityText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    /// The small family fits two windows; keep their reset-footer grouping.
    private func compactGroups(_ snapshot: UsageSnapshot) -> [[LimitWindow]] {
        // Cursor exposes Composer and API as distinct monthly quotas even
        // though they share a billing-cycle reset. Keep a reset line beneath
        // each row so the small widget stays aligned with the other providers.
        if snapshot.provider == .cursor {
            return snapshot.windows.prefix(2).map { [$0] }
        }

        var remaining = 2
        var groups: [[LimitWindow]] = []
        for group in snapshot.windowGroups {
            guard remaining > 0 else { break }
            groups.append(Array(group.prefix(remaining)))
            remaining -= min(group.count, remaining)
        }
        return groups
    }
}

/// accessoryCircular: gauge of remaining percent for the account's most-consumed window.
struct CircularGaugeView: View {
    let state: AccountState

    var body: some View {
        if let worst = state.snapshot?.worstWindow {
            Gauge(value: worst.remainingPercent, in: 0...100) {
                ProviderLogo(provider: state.account.provider, size: 12)
            } currentValueLabel: {
                Text("\(Int(worst.remainingPercent.rounded()))%")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(worst.barColor)
        } else {
            Gauge(value: 0, in: 0...100) {
                ProviderLogo(provider: state.account.provider, size: 12)
            } currentValueLabel: {
                Text("—")
            }
            .gaugeStyle(.accessoryCircular)
        }
    }
}

// MARK: - All accounts (systemSmall list / systemMedium bars / systemLarge detail)

struct AllAccountsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AllAccountsEntry

    init(entry: AllAccountsEntry) {
        self.entry = entry
        AmmoLog.widgetRender.debug("Constructing All Accounts widget with \(entry.states.count, privacy: .public) states")
    }

    var body: some View {
        if entry.states.isEmpty {
            SetupHintView()
        } else {
            switch family {
            case .systemSmall:
                ProviderListView(states: entry.states)
            case .systemLarge:
                LargeAccountsView(states: entry.states, referenceDate: entry.date)
            default:
                MediumAccountsView(states: entry.states)
            }
        }
    }
}

/// systemSmall: two compact provider cards — full name, percent, and bar.
struct ProviderListView: View {
    let states: [AccountState]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(states.prefix(2)) { state in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        ProviderLogo(provider: state.account.provider, size: 18)
                        Text(state.account.label)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .layoutPriority(1)
                        Spacer(minLength: 4)
                        if let worst = state.snapshot?.worstWindow {
                            Text(worst.remainingPercentText)
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(worst.isRunningLow ? worst.barColor : .primary)
                                .widgetAccentable()
                                .fixedSize(horizontal: true, vertical: false)
                        } else {
                            Text(state.widgetCompactAvailabilityText)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let worst = state.snapshot?.worstWindow {
                        CapsuleBar(fraction: worst.remainingPercent / 100,
                                   color: worst.barColor,
                                   height: 6)
                    } else {
                        CapsuleBar(fraction: 0, color: .secondary, height: 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: .topLeading)
    }
}

/// systemMedium: one row per account — logo, name, bar, percent.
struct MediumAccountsView: View {
    let states: [AccountState]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(states.prefix(4)) { state in
                HStack(spacing: 8) {
                    ProviderLogo(provider: state.account.provider, size: 20)
                    Text(state.account.label)
                        .font(.body)
                        .lineLimit(1)
                        .frame(width: 76, alignment: .leading)
                    if let worst = state.snapshot?.worstWindow {
                        CapsuleBar(fraction: worst.remainingPercent / 100,
                                   color: worst.barColor, height: 7)
                        Text(worst.remainingPercentText)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(worst.isRunningLow ? worst.barColor : .primary)
                            .widgetAccentable()
                            .frame(width: 48, alignment: .trailing)
                    } else {
                        Text(state.widgetCompactAvailabilityText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }
}

/// systemLarge: full detail for the first two accounts. Each account is capped
/// at three windows so both providers always retain a visible, stable region.
struct LargeAccountsView: View {
    let states: [AccountState]
    let referenceDate: Date

    private var visibleStates: [AccountState] {
        Array(states.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let first = visibleStates.first {
                LargeProviderSection(state: first, referenceDate: referenceDate)
            }
            if visibleStates.count > 1 {
                Divider()
                LargeProviderSection(state: visibleStates[1], referenceDate: referenceDate)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: .topLeading)
    }
}

private struct LargeProviderSection: View {
    let state: AccountState
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                ProviderLogo(provider: state.account.provider, size: 20)
                Text(state.account.label)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if let snapshot = state.snapshot, !snapshot.windows.isEmpty {
                ForEach(detailGroups(snapshot), id: \.first!.id) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(group) { window in
                            UsageWindowRow(window: window,
                                           font: .subheadline,
                                           barHeight: 7,
                                           spacing: 3)
                        }
                        ResetStatusLine(snapshot: snapshot,
                                        group: group,
                                        referenceDate: referenceDate,
                                        font: .footnote)
                    }
                }
            } else {
                Text(state.widgetAvailabilityText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailGroups(_ snapshot: UsageSnapshot) -> [[LimitWindow]] {
        var remaining = 3
        var groups: [[LimitWindow]] = []
        for group in snapshot.windowGroups {
            guard remaining > 0 else { break }
            let visibleGroup = Array(group.prefix(remaining))
            groups.append(visibleGroup)
            remaining -= visibleGroup.count
        }
        return groups
    }
}

private extension AccountState {
    var widgetAvailabilityText: String {
        if snapshot?.onDemand?.isEmpty == false { return "Metered usage only" }
        return activeFailure == nil ? "No usage limits yet" : "Update paused — open Ammo"
    }

    var widgetCompactAvailabilityText: String {
        if snapshot?.onDemand?.isEmpty == false { return "Metered" }
        return activeFailure == nil ? "No limits" : "Paused"
    }
}
