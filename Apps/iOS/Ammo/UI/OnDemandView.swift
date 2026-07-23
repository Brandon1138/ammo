import SwiftUI
import UsageKit

struct OnDemandView: View {
    @Environment(AccountStore.self) private var store
    @State private var billingAccount: StoredAccount?
    @State private var referenceDate = Date.now

    var body: some View {
        NavigationStack {
            Group {
                if store.states.isEmpty {
                    ContentUnavailableView {
                        Label("No accounts yet", systemImage: "bolt.slash")
                    } description: {
                        Text("Add an account from Usage to see its on-demand capacity.")
                    }
                } else if statesWithOnDemand.isEmpty {
                    ContentUnavailableView {
                        Label("No on-demand data", systemImage: "bolt.slash")
                    } description: {
                        Text("Your providers have not reported an on-demand balance or spending limit.")
                    } actions: {
                        Button("Refresh") {
                            Task { await store.refreshAll(reason: .manual) }
                        }
                    }
                } else {
                    accountList
                }
            }
            .navigationTitle("On-demand")
            .sheet(item: $billingAccount) { account in
                CodexBillingView(account: account)
            }
            .task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(60))
                    } catch {
                        return
                    }
                    referenceDate = .now
                }
            }
        }
    }

    private var statesWithOnDemand: [AccountState] {
        store.states.filter {
            $0.account.provider == .codex || $0.snapshot?.onDemand?.isEmpty == false
        }
    }

    private var accountList: some View {
        List {
            ForEach(statesWithOnDemand) { state in
                AccountOnDemandSection(
                    state: state,
                    referenceDate: referenceDate,
                    connectBilling: { billingAccount = state.account })
            }
        }
        .refreshable {
            await store.refreshAll(reason: .manual)
        }
        .listSectionSpacing(.custom(10))
    }
}

private struct AccountOnDemandSection: View {
    let state: AccountState
    let referenceDate: Date
    let connectBilling: () -> Void

    var body: some View {
        Section {
            ForEach(state.snapshot?.onDemand ?? []) { usage in
                OnDemandUsageRow(usage: usage, referenceDate: referenceDate)
                    .padding(.vertical, 4)
            }
            if state.account.provider == .codex {
                Button(action: connectBilling) {
                    Label(codexBillingButtonTitle, systemImage: "building.2.crop.circle")
                }
            }
        } header: {
            HStack(spacing: 7) {
                ProviderLogo(provider: state.account.provider, size: 20)
                Text(state.account.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
                if let plan = state.snapshot?.displayPlan {
                    Text(plan)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .textCase(nil)
                }
            }
        } footer: {
            if let updatedAt = state.updatedAt {
                Text("Updated \(elapsedText(since: updatedAt)) ago")
                    .textCase(nil)
            }
        }
    }

    private var codexBillingButtonTitle: String {
        let balance = state.snapshot?.onDemand?
            .first(where: { $0.id == "codex-usage-credits" })?
            .remainingAmount
        return balance == nil ? "Connect workspace billing" : "Update workspace balance"
    }

    private func elapsedText(since date: Date) -> String {
        let seconds = max(0, Int(referenceDate.timeIntervalSince(date)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }
}

private struct OnDemandUsageRow: View {
    let usage: OnDemandUsage
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                usageLabel
                statusBadge
            }

            Text(primaryText)
                .font(.headline.weight(.semibold).monospacedDigit())
                .foregroundStyle(primaryColor)
                .fixedSize(horizontal: false, vertical: true)

            if let fraction = usage.remainingFraction, usage.isEnabled != false {
                CapsuleBar(fraction: fraction, color: meterColor, height: 8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(detailText)
                Text(scopeText)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let resetsAt = usage.resetsAt, resetsAt > referenceDate {
                Label {
                    Text("Resets in \(remainingText(until: resetsAt))")
                } icon: {
                    Image(systemName: "arrow.clockwise")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let expiresAt = usage.expiresAt {
                Label {
                    if expiresAt > referenceDate {
                        Text("Expires in \(remainingText(until: expiresAt))")
                    } else {
                        Text("Expired")
                    }
                } icon: {
                    Image(systemName: "calendar.badge.exclamationmark")
                }
                .font(.footnote)
                .foregroundStyle(expiresAt > referenceDate ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var usageLabel: some View {
        Text(usage.label)
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.caption.weight(.medium))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.12), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }

    private var primaryText: String {
        if usage.isEnabled == false { return "On-demand is off" }
        if usage.isUnlimited { return "Unlimited" }
        if let remaining = usage.remainingAmount { return "\(amount(remaining)) remaining" }
        if let used = usage.used { return "\(amount(used)) used" }
        if usage.effectiveUnit == .credits { return "Balance unavailable" }
        return "Amount unavailable"
    }

    private var detailText: String {
        if usage.isEnabled == false {
            if let limit = usage.limit { return "\(amount(limit)) configured limit" }
            return "Not available for paid continuation"
        }
        if let equivalentAmount = usage.equivalentAmount,
           let code = usage.equivalentCurrencyCode {
            return "\(money(equivalentAmount, currencyCode: code)) equivalent"
        }
        if usage.isUnlimited, let used = usage.used { return "\(amount(used)) used" }
        if let used = usage.used, let limit = usage.limit {
            return "\(amount(used)) of \(amount(limit)) used"
        }
        if usage.kind == .creditBalance {
            return usage.remainingAmount == nil
                ? "Connect workspace billing to read the balance"
                : "Prepaid usage balance"
        }
        if let limit = usage.limit { return "\(amount(limit)) limit" }
        return "Provider-reported capacity"
    }

    private var statusText: String {
        if usage.isEnabled == false { return "Off" }
        if usage.isUnlimited { return "Unlimited" }
        if usage.isExhausted { return "Exhausted" }
        if usage.remainingAmount == nil && usage.effectiveUnit == .credits { return "Connect" }
        if (usage.used ?? 0) > 0 { return "Active" }
        return "Ready"
    }

    private var scopeText: String {
        switch usage.scope {
        case .personal: "Personal"
        case .team: "Team"
        case .organization: "Organization"
        }
    }

    private var statusColor: Color {
        if usage.isEnabled == false { return .secondary }
        if usage.isExhausted { return .red }
        return .accentColor
    }

    private var primaryColor: Color {
        usage.isExhausted ? .red : .primary
    }

    private var meterColor: Color {
        guard let remaining = usage.remainingFraction else { return .accentColor }
        if remaining <= 0.1 { return .red }
        if remaining <= 0.25 { return .orange }
        return .accentColor
    }

    private func amount(_ value: Double) -> String {
        if usage.effectiveUnit == .credits {
            return value.formatted(
                .number.grouping(.automatic).precision(.fractionLength(0))) + " credits"
        }
        return money(value, currencyCode: usage.currencyCode)
    }

    private func money(_ amount: Double, currencyCode: String) -> String {
        amount.formatted(
            .currency(code: currencyCode)
            .precision(.fractionLength(2))
        )
    }

    private func remainingText(until date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(referenceDate)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }
}

struct OnDemandSummaryButton: View {
    let snapshot: UsageSnapshot
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                Text(summaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens on-demand usage")
    }

    private var summaryText: String {
        let entries = snapshot.onDemand ?? []
        if entries.allSatisfy({ $0.isEnabled == false }) { return "On-demand off" }
        guard let entry = entries.first(where: { $0.isEnabled != false && $0.kind == .creditBalance })
            ?? entries.first(where: { $0.isEnabled != false && $0.scope == .personal })
            ?? entries.first(where: { $0.isEnabled != false })
            ?? entries.first
        else { return "On-demand" }
        if entry.isUnlimited { return "On-demand unlimited" }
        if let remaining = entry.remainingAmount {
            let formatted: String
            if entry.effectiveUnit == .credits {
                formatted = remaining.formatted(
                    .number.grouping(.automatic).precision(.fractionLength(0))) + " credits"
            } else {
                formatted = remaining.formatted(
                    .currency(code: entry.currencyCode)
                    .precision(.fractionLength(2))
                )
            }
            return "On-demand · \(formatted) remaining"
        }
        return entry.effectiveUnit == .credits
            ? "On-demand · balance unavailable"
            : "On-demand amount unavailable"
    }
}
