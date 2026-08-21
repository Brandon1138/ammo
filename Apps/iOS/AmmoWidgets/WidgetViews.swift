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

/// systemSmall: logo + bold name header, then up to three windows as
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
                // Claude's optional model bucket only earns a row where the
                // family has the height for it. ViewThatFits drops back to the
                // two-window layout rather than clipping the third bar.
                ViewThatFits(in: .vertical) {
                    windows(snapshot: snapshot, limit: 3)
                    windows(snapshot: snapshot, limit: 2)
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

    private func windows(snapshot: UsageSnapshot, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(compactGroups(snapshot, limit: limit), id: \.first!.id) { group in
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
        }
    }

    /// Up to `limit` rows, preserving Claude's optional model bucket. Plans
    /// without that provider-reported window collapse naturally and reserve no
    /// blank space.
    private func compactGroups(_ snapshot: UsageSnapshot, limit: Int) -> [[LimitWindow]] {
        // Cursor exposes Cursor Models and Other Models as distinct monthly
        // quotas even though they share a billing-cycle reset. Keep a reset
        // line beneath each row so the small widget stays aligned with the
        // other providers.
        if snapshot.provider == .cursor {
            return snapshot.windows.prefix(min(2, limit)).map { [$0] }
        }

        return snapshot.widgetWindowGroups(limitedTo: limit)
    }
}

/// accessoryCircular: provider-reported window drives open gauge chrome and,
/// when another window exists, its remaining percent becomes numeric value.
/// Single-window providers show a marker for their real window. Providers that
/// report spend instead of a window draw the same chrome from their on-demand
/// pool, so every account on the Lock Screen carries live value and the logo in
/// the six o'clock gap.
struct CircularGaugeView: View {
    let state: AccountState
    let referenceDate: Date

    @ViewBuilder
    var body: some View {
        if let presentation = state.lockScreenUsagePresentation {
            if presentation.numericWindow != nil {
                usageGauge(presentation: presentation)
                    .gaugeStyle(AmmoAccessoryCircularGaugeStyle(variant: .fill))
                    .statusOverlay(symbol: failureSymbol)
            } else {
                usageGauge(presentation: presentation)
                    .gaugeStyle(AmmoAccessoryCircularGaugeStyle(variant: .marker))
                    .statusOverlay(symbol: failureSymbol)
            }
        } else if let metered = state.lockScreenMeteredPresentation {
            // A pool with capacity can deplete the arc; an amount-only pool has
            // nothing to deplete, so it keeps the full track and the dot.
            let variant: AmmoAccessoryCircularGaugeStyle.Variant =
                metered.remainingFraction == nil ? .marker : .fill
            meteredGauge(presentation: metered)
                .gaugeStyle(AmmoAccessoryCircularGaugeStyle(variant: variant))
                .statusOverlay(symbol: failureSymbol)
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
            .gaugeStyle(AmmoAccessoryCircularGaugeStyle(variant: .marker))
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

    private func meteredGauge(
        presentation: MeteredLockScreenPresentation
    ) -> some View {
        Gauge(value: presentation.remainingFraction ?? 1, in: 0...1) {
            ProviderLogo(provider: state.account.provider, size: 12)
        } currentValueLabel: {
            if let centerText = presentation.centerText {
                Text(centerText)
            } else {
                Image(systemName: presentation.centerFallbackSymbol)
            }
        }
        .tint(meterColor(presentation.remainingFraction ?? 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(meteredAccessibilityLabel(presentation: presentation))
    }

    /// Failure is the only overlay the Lock Screen shows. Staleness needs no
    /// marker there: gauges refresh with the app and with background refresh,
    /// so a stale badge was a relic of the era when the widget fetched for
    /// itself.
    private var failureSymbol: String? {
        state.activeFailure != nil ? "exclamationmark.circle.fill" : nil
    }

    private func meteredAccessibilityLabel(
        presentation: MeteredLockScreenPresentation
    ) -> String {
        var values = [
            "\(state.account.provider.displayName) \(presentation.accessibilityDescription)"
        ]
        if state.activeFailure != nil {
            values.append("Update failed; showing cached data")
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

/// Shared by OpenRouter's XL bar and every Lock Screen spend gauge.
private func meterColor(_ remainingFraction: Double) -> Color {
    if remainingFraction <= 0.1 {
        .red
    } else if remainingFraction <= 0.25 {
        .orange
    } else {
        .blue
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
        for window in snapshot.windows
        where window.kind == .modelScoped && window.id != hero.id {
            rows.append(LedgerItem(
                id: "model-\(window.id)",
                label: window.label,
                value: window.remainingPercentText,
                tint: window.isRunningLow ? window.barColor : .primary))
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
        if WidgetProviderPanels.isProviderBoard(family) {
            // The board keeps a panel per provider, so an empty configuration
            // still explains itself provider by provider.
            ProviderBoardView(states: entry.states, referenceDate: entry.date)
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
                    if let window = state.widgetCompactModelWindow {
                        CompactModelWindowRow(window: window, barHeight: 4)
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
        // Four rows already use nearly the whole family; a model bucket only
        // fits once the rows sit closer together, and the last resort is the
        // plain four-row layout rather than a clipped fifth line.
        ViewThatFits(in: .vertical) {
            rows(spacing: 12, includesModelWindows: true)
            rows(spacing: 8, includesModelWindows: true)
            rows(spacing: 12, includesModelWindows: false)
        }
    }

    private func rows(spacing: CGFloat, includesModelWindows: Bool) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(states.prefix(4)) { state in
                VStack(alignment: .leading, spacing: 3) {
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
                    if includesModelWindows,
                       let window = state.widgetCompactModelWindow {
                        CompactModelWindowRow(window: window, leadingInset: 28, barHeight: 4)
                    }
                }
            }
        }
    }
}

private struct CompactModelWindowRow: View {
    let window: LimitWindow
    var leadingInset: CGFloat = 0
    var barHeight: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Text(window.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 44, alignment: .leading)
            CapsuleBar(fraction: window.remainingPercent / 100,
                       color: window.barColor,
                       height: barHeight)
            Text(window.remainingPercentText)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(window.isRunningLow ? window.barColor : .secondary)
                .widgetAccentable()
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, leadingInset)
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
    let provider: ProviderID
    let state: AccountState?
    let referenceDate: Date
    var windowLimit = 3

    init(state: AccountState, referenceDate: Date, windowLimit: Int = 3) {
        provider = state.account.provider
        self.state = state
        self.referenceDate = referenceDate
        self.windowLimit = windowLimit
    }

    init(slot: WidgetProviderSlot, referenceDate: Date, windowLimit: Int = 3) {
        provider = slot.provider
        state = slot.state
        self.referenceDate = referenceDate
        self.windowLimit = windowLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                ProviderLogo(provider: provider, size: 20)
                Text(state?.account.label ?? provider.displayName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if let state, let snapshot = state.snapshot, !snapshot.windows.isEmpty {
                ForEach(snapshot.widgetWindowGroups(limitedTo: windowLimit), id: \.first!.id) { group in
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
                if let balance = snapshot.verifiedMonetaryOnDemandBalance,
                   let remaining = balance.remainingAmount {
                    Text("\(remaining.formatted(.currency(code: balance.currencyCode).precision(.fractionLength(2)))) on-demand")
                        .font(.footnote)
                        .foregroundStyle(balance.isExhausted ? .red : .secondary)
                        .lineLimit(1)
                }
            } else if let state, let snapshot = state.snapshot,
                      let presentation = OpenRouterKeyPresentation(snapshot: snapshot) {
                OpenRouterCreditsPanel(
                    presentation: presentation,
                    referenceDate: referenceDate)
            } else if let state {
                Text(state.widgetAvailabilityText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not configured. Add or select \(provider.displayName) in Ammo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - All accounts (systemExtraLargePortrait)

/// systemExtraLargePortrait: systemLarge's typography, bars, spacing, and
/// divider-separated sections extended to four providers. No nested card chrome.
struct ProviderBoardView: View {
    let states: [AccountState]
    let referenceDate: Date

    var body: some View {
        let slots = WidgetProviderPanels.slots(states: states)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                if index > 0 { Divider() }
                LargeProviderSection(
                    slot: slot,
                    referenceDate: referenceDate,
                    windowLimit: WidgetProviderPanels.boardWindowLimit)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// OpenRouter reports money and one static entitlement, never a percentage
/// window, so its section meters credits and labels the free-model request cap
/// the key is subject to. The cap is not a counter and is omitted entirely when
/// the key endpoint does not report a tier.
private struct OpenRouterCreditsPanel: View {
    let presentation: OpenRouterKeyPresentation
    let referenceDate: Date

    var body: some View {
        // A provider section is compact, so the money, the
        // entitlement badge, and the reset all share lines with something else
        // rather than each claiming one.
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(presentation.headline)
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(presentation.isExhausted ? .red : .primary)
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                if let badge = presentation.tierBadge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            if let fraction = presentation.remainingFraction {
                CapsuleBar(
                    fraction: fraction,
                    color: meterColor(fraction),
                    height: 7)
            }
            HStack(spacing: 8) {
                Text(presentation.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
                Spacer(minLength: 0)
            }
            if let daily = presentation.dailyDetail {
                Text(daily)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

}

@available(iOS 27.0, *)
#Preview("XL with Fable", as: .systemExtraLargePortrait) {
    AmmoAllAccountsWidget()
} timeline: {
    AllAccountsEntry(
        date: .now,
        states: WidgetAccountOrder.defaultOrder(AccountState.providerBoardPlaceholders),
        revision: nil)
}

@available(iOS 27.0, *)
#Preview("XL without Fable", as: .systemExtraLargePortrait) {
    AmmoAllAccountsWidget()
} timeline: {
    AllAccountsEntry(
        date: .now,
        states: WidgetAccountOrder.defaultOrder(AccountState.providerBoardPlaceholdersWithoutFable),
        revision: nil)
}
