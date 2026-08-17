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
                CircularGaugeView(state: state, referenceDate: entry.date)
            case .systemMedium:
                MediumAccountView(state: state, referenceDate: entry.date)
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

/// accessoryCircular: provider-reported window drives native capacity
/// indicator and, when another window exists, its remaining percent becomes
/// numeric value. Single-window providers show only their real window.
struct CircularGaugeView: View {
    let state: AccountState
    let referenceDate: Date

    @ViewBuilder
    var body: some View {
        if let snapshot = state.snapshot,
           let presentation = LockScreenUsagePresentation(snapshot: snapshot) {
            if presentation.numericWindow != nil {
                usageGauge(presentation: presentation)
                    .gaugeStyle(.accessoryCircularCapacity)
                    .statusOverlay(symbol: statusSymbol(for: presentation))
            } else {
                usageGauge(presentation: presentation)
                    .gaugeStyle(.accessoryCircular)
                    .statusOverlay(symbol: statusSymbol(for: presentation))
            }
        } else if state.hasWidgetMeteredUsage {
            VStack(spacing: 1) {
                ProviderLogo(provider: state.account.provider, size: 17)
                Image(systemName: "dollarsign")
                    .font(.system(size: 8, weight: .semibold))
            }
            .statusOverlay(symbol: state.widgetStatusSymbol(at: referenceDate))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(meteredAccessibilityLabel)
        } else {
            Gauge(value: 0, in: 0...100) {
                ProviderLogo(provider: state.account.provider, size: 12)
            } currentValueLabel: {
                if state.activeFailure != nil || state.snapshot != nil {
                    Image(systemName: "exclamationmark")
                } else {
                    Text("…")
                }
            }
            .gaugeStyle(.accessoryCircular)
            .accessibilityLabel(emptyAccessibilityLabel)
        }
    }

    private func usageGauge(
        presentation: LockScreenUsagePresentation
    ) -> some View {
        let indicator = presentation.indicatorWindow
        let numeric = presentation.numericWindow ?? indicator
        return Gauge(value: indicator.remainingPercent, in: 0...100) {
            ProviderLogo(provider: state.account.provider, size: 12)
        } currentValueLabel: {
            Text(numeric.remainingPercentText)
        }
        .tint(indicator.barColor)
        .accessibilityLabel(accessibilityLabel(for: presentation))
    }

    private func statusSymbol(
        for presentation: LockScreenUsagePresentation
    ) -> String? {
        if state.activeFailure != nil {
            return "exclamationmark.circle.fill"
        }
        if presentation.isStale(at: referenceDate) {
            return "clock.badge.exclamationmark"
        }
        return nil
    }

    private var meteredAccessibilityLabel: String {
        var values = [
            "\(state.account.provider.displayName) reports spending without a percentage limit"
        ]
        if state.activeFailure != nil {
            values.append("Update failed; showing cached data")
        } else if state.widgetStatusSymbol(at: referenceDate) != nil {
            values.append("Update is stale")
        }
        return values.joined(separator: ", ")
    }

    private func accessibilityLabel(
        for presentation: LockScreenUsagePresentation
    ) -> String {
        var values = [
            "\(presentation.indicatorWindow.label) \(presentation.indicatorWindow.remainingPercentText) remaining"
        ]
        if let numeric = presentation.numericWindow {
            values.append("\(numeric.label) \(numeric.remainingPercentText) remaining")
        }
        if state.activeFailure != nil {
            values.append("Update failed; showing cached data")
        } else if presentation.isStale(at: referenceDate) {
            values.append("Update is stale")
        }
        return values.joined(separator: ", ")
    }

    private var emptyAccessibilityLabel: String {
        if state.activeFailure != nil {
            return "\(state.account.provider.displayName) update failed; open Ammo"
        }
        if state.snapshot != nil {
            return "\(state.account.provider.displayName) returned no usage windows"
        }
        return "\(state.account.provider.displayName) is waiting for its first update"
    }
}

private extension View {
    @ViewBuilder
    func statusOverlay(symbol: String?) -> some View {
        if let symbol {
            overlay(alignment: .topTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
                    .accessibilityHidden(true)
            }
        } else {
            self
        }
    }
}

// MARK: - Single account medium (Headline + Ledger)

/// systemMedium, one selected account. Dominant headline meter fills left;
/// right ledger carries honest, unit-native reset, credit, and on-demand facts.
/// Rows appear only when provider-reported data exists.
struct MediumAccountView: View {
    let state: AccountState
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let snapshot = state.snapshot, let hero = snapshot.worstWindow {
                content(snapshot: snapshot, hero: hero)
            } else {
                Spacer(minLength: 0)
                Text(state.widgetAvailabilityText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 7) {
            ProviderLogo(provider: state.account.provider, size: 20)
            Text(state.account.label)
                .font(.headline)
                .lineLimit(1)
                .layoutPriority(1)
            if let planBadge {
                Text(planBadge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    private func content(snapshot: UsageSnapshot, hero: LimitWindow) -> some View {
        let rows = ledgerRows(snapshot: snapshot, hero: hero)
        return HStack(alignment: .top, spacing: 14) {
            headline(hero: hero)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !rows.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(rows) { row in
                        HStack(spacing: 6) {
                            Text(row.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(row.value)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(row.tint)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 128, alignment: .leading)
            }
        }
    }

    private func headline(hero: LimitWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(hero.remainingPercentText)
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(hero.isRunningLow ? hero.barColor : .primary)
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(qualifier(for: hero))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            CapsuleBar(fraction: hero.remainingPercent / 100, color: hero.barColor, height: 9)
            if let freshness {
                Text(freshness)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private struct LedgerItem: Identifiable {
        let id: String
        let label: String
        let value: String
        var tint: Color = .primary
    }

    /// Money, provider credits, and window percentages stay in native units.
    /// Legacy on-demand values without MIK-26 provenance never render here.
    private func ledgerRows(snapshot: UsageSnapshot, hero: LimitWindow) -> [LedgerItem] {
        var rows: [LedgerItem] = []
        if let reset = resetValue(for: hero) {
            rows.append(LedgerItem(id: "resets", label: "Resets", value: reset))
        }
        if let banked = snapshot.resetCreditsAvailable, banked > 0 {
            rows.append(LedgerItem(id: "banked", label: "Banked",
                                   value: "\(banked) reset\(banked == 1 ? "" : "s")"))
        }
        if let usage = snapshot.verifiedMonetaryOnDemandBalance,
           let remaining = usage.remainingAmount {
            rows.append(LedgerItem(
                id: "on-demand-\(usage.id)",
                label: "On-demand",
                value: remaining.formatted(
                    .currency(code: usage.currencyCode)
                    .precision(.fractionLength(2))),
                tint: usage.isExhausted ? .red : .primary))
        }
        return rows
    }

    private func resetValue(for hero: LimitWindow) -> String? {
        guard let resetsAt = hero.resetsAt else { return nil }
        if resetsAt <= referenceDate { return "Due" }
        return compactDuration(Int(resetsAt.timeIntervalSince(referenceDate)))
    }

    private var planBadge: String? {
        state.snapshot?.displayPlan
    }

    private var freshness: String? {
        guard let updatedAt = state.updatedAt else { return nil }
        return "Updated \(compactDuration(Int(referenceDate.timeIntervalSince(updatedAt)))) ago"
    }

    private func qualifier(for hero: LimitWindow) -> String {
        switch hero.kind {
        case .session: "left this session"
        case .weekly: "left this week"
        case .monthly: "left this month"
        case .modelScoped, .unknown: "left"
        }
    }

    private func compactDuration(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
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
        if family == .systemExtraLarge {
            // The extra-large grid keeps a panel per provider, so an empty
            // configuration still explains itself provider by provider.
            ExtraLargeAccountsView(states: entry.states, referenceDate: entry.date)
        } else if entry.states.isEmpty {
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
                        if let worst = state.widgetPercentageWindow {
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
                    if let worst = state.widgetPercentageWindow {
                        CapsuleBar(fraction: worst.remainingPercent / 100,
                                   color: worst.barColor,
                                   height: 6)
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
                    if let worst = state.widgetPercentageWindow {
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
        snapshot.windowGroups(limitedTo: 3)
    }
}

// MARK: - All accounts (systemExtraLarge)

/// systemExtraLarge: a 2×2 grid with one panel per shipping provider. Unlike the
/// smaller families, which show only what is configured, this layout is a fixed
/// board — a provider without an account keeps its panel and says why it is
/// empty, so the grid never reads as a failed render.
struct ExtraLargeAccountsView: View {
    let states: [AccountState]
    let referenceDate: Date

    var body: some View {
        let panels = WidgetProviderPanels.slots(states: states)
        VStack(spacing: 10) {
            ForEach(Array(stride(from: 0, to: panels.count, by: 2)), id: \.self) { index in
                HStack(spacing: 10) {
                    ExtraLargeProviderPanel(slot: panels[index],
                                            referenceDate: referenceDate)
                    if index + 1 < panels.count {
                        ExtraLargeProviderPanel(slot: panels[index + 1],
                                                referenceDate: referenceDate)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ExtraLargeProviderPanel: View {
    let slot: WidgetProviderSlot
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            content
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Same phrasing the Lock Screen metered label uses, so the header marker is
    /// never a glyph without a spoken meaning.
    private var statusNotice: String? {
        guard let state = slot.state else { return nil }
        if state.activeFailure != nil { return "Update failed; showing cached data" }
        return state.widgetStatusSymbol(at: referenceDate) != nil ? "Update is stale" : nil
    }

    private var header: some View {
        HStack(spacing: 8) {
            ProviderLogo(provider: slot.provider, size: 22)
            Text(slot.state?.account.label ?? slot.provider.displayName)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .layoutPriority(1)
            if let plan = slot.state?.snapshot?.displayPlan {
                Text(plan)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Spacer(minLength: 0)
            if let symbol = slot.state?.widgetStatusSymbol(at: referenceDate),
               let statusNotice {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(statusNotice)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let state = slot.state {
            if let snapshot = state.snapshot, !snapshot.windows.isEmpty {
                windows(state: state, snapshot: snapshot)
            } else if let snapshot = state.snapshot,
                      let presentation = OpenRouterKeyPresentation(snapshot: snapshot) {
                OpenRouterCreditsPanel(presentation: presentation,
                                       referenceDate: referenceDate,
                                       statusNotice: statusNotice)
            } else {
                unavailable(state: state)
            }
        } else {
            missingAccount
        }
    }

    private func windows(state: AccountState, snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Grouped by position: a group is identified by where it sits in the
            // truncated list, so no window id has to be unwrapped or unique.
            let groups = Array(snapshot.windowGroups(limitedTo: 3).enumerated())
            ForEach(groups, id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(group) { window in
                        UsageWindowRow(window: window,
                                       font: .subheadline,
                                       barHeight: 8,
                                       spacing: 3)
                    }
                    ResetStatusLine(snapshot: snapshot,
                                    group: group,
                                    referenceDate: referenceDate,
                                    font: .footnote)
                }
            }
            if let balance = snapshot.verifiedMonetaryOnDemandBalance,
               let remaining = balance.remainingAmount {
                Text("\(remaining.formatted(.currency(code: balance.currencyCode).precision(.fractionLength(2)))) on-demand")
                    .font(.footnote)
                    .foregroundStyle(balance.isExhausted ? .red : .secondary)
                    .lineLimit(1)
            }
        }
    }

    /// A configured account that has no usable meter yet still states its
    /// condition — waiting for a first update, paused after a failure, or
    /// reporting money Ammo will not redraw as a percentage.
    private func unavailable(state: AccountState) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(state.widgetAvailabilityText,
                  systemImage: state.activeFailure == nil
                      ? "clock.arrow.circlepath"
                      : "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let balance = state.snapshot?.verifiedMonetaryOnDemandBalance,
               let remaining = balance.remainingAmount {
                Text("\(remaining.formatted(.currency(code: balance.currencyCode).precision(.fractionLength(2)))) remaining")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(balance.isExhausted ? .red : .primary)
                    .lineLimit(1)
            }
        }
    }

    private var missingAccount: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Not configured")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Add or select \(slot.provider.displayName) in Ammo.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

/// OpenRouter reports money and one static entitlement, never a percentage
/// window, so its panel meters credits and labels the free-model request cap
/// the key is subject to. The cap is not a counter and is omitted entirely when
/// the key endpoint does not report a tier.
private struct OpenRouterCreditsPanel: View {
    let presentation: OpenRouterKeyPresentation
    let referenceDate: Date
    /// Set when the panel is drawing a cached snapshot. Money is stated as a
    /// present-tense fact, so a failed or stale fetch has to say so visibly and
    /// not only through the header glyph.
    var statusNotice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(presentation.headline)
                .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(presentation.isExhausted ? .red : .primary)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let statusNotice {
                Label(statusNotice, systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            if let fraction = presentation.remainingFraction {
                CapsuleBar(fraction: fraction, color: meterColor(fraction), height: 8)
            }
            Text(presentation.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let daily = presentation.dailyDetail {
                Text(daily)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let resetsAt = presentation.resetsAt {
                if resetsAt > referenceDate {
                    ResetLine(date: resetsAt, referenceDate: referenceDate, font: .footnote)
                } else {
                    Label("Reset due", systemImage: "arrow.clockwise")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let badge = presentation.tierBadge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    /// Same thresholds as the window meters: amber once a quarter of the budget
    /// is left, red in the last tenth.
    private func meterColor(_ fraction: Double) -> Color {
        if fraction <= 0.1 { .red } else if fraction <= 0.25 { .orange } else { .blue }
    }
}
