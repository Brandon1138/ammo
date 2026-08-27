import StoreKit
import SwiftUI
import UsageKit

struct OnDemandView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var referenceDate = Date.now
    @State private var storefrontCountryCode: String?
    @State private var billingAvailability = CodexWorkspaceBillingAvailability.checking
    @State private var isConfirmingWorkspaceBilling = false
    @State private var presentedSheet: AmmoTabSheet?

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
            .ammoTabHeader(sheet: $presentedSheet)
            .confirmationDialog(
                "Update workspace balance",
                isPresented: $isConfirmingWorkspaceBilling,
                titleVisibility: .visible
            ) {
                Button("Continue in Browser") {
                    openCodexDestination(.updateWorkspaceBalance)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Workspace Owners can manage shared Business credits. Sign in to ChatGPT and choose the correct workspace.")
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
            .task {
                let storefront = await Storefront.current
                storefrontCountryCode = storefront?.countryCode
                billingAvailability = CodexWorkspaceBillingPolicy.availability(
                    storefrontCountryCode: storefront?.countryCode)
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
                    billingAvailability: billingAvailability,
                    updateWorkspaceBalance: {
                        guard billingAvailability.permitsWorkspaceBilling else { return }
                        isConfirmingWorkspaceBilling = true
                    },
                    viewCodexUsage: {
                        openCodexDestination(.viewUsage)
                    })
            }
        }
        .refreshable {
            await store.refreshAll(reason: .manual)
        }
        .listSectionSpacing(.custom(10))
    }

    private func openCodexDestination(_ action: CodexExternalAction) {
        guard let destination = CodexWorkspaceBillingPolicy.destination(
            for: action,
            storefrontCountryCode: storefrontCountryCode)
        else { return }
        openURL(destination)
    }
}

private struct AccountOnDemandSection: View {
    let state: AccountState
    let referenceDate: Date
    let billingAvailability: CodexWorkspaceBillingAvailability
    let updateWorkspaceBalance: () -> Void
    let viewCodexUsage: () -> Void

    var body: some View {
        Section {
            ForEach(onDemandRows) { usage in
                OnDemandUsageRow(usage: usage, referenceDate: referenceDate)
                    .padding(.vertical, 4)
            }
            if state.account.provider == .codex {
                Button(action: updateWorkspaceBalance) {
                    Label("Update workspace balance", systemImage: "building.2.crop.circle")
                }
                .disabled(!billingAvailability.permitsWorkspaceBilling)

                Button(action: viewCodexUsage) {
                    Label("View Codex usage", systemImage: "safari")
                }

                Text(workspaceBillingNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    /// OpenRouter's daily-spend pool is a one-day total, not capacity. This list
    /// describes every pool through limit/remaining language, which would read a
    /// day's spend as unlimited capacity, so the pool stays out of it and is
    /// shown only where it is labelled as today's spend.
    private var onDemandRows: [OnDemandUsage] {
        (state.snapshot?.onDemand ?? []).filter {
            $0.id != OpenRouterKeyPresentation.dailyPoolID
        }
    }

    private var workspaceBillingNote: String {
        switch billingAvailability {
        case .checking:
            "Checking App Store region. Workspace Owners manage shared Business credits in ChatGPT."
        case .allowed:
            "Workspace Owners manage shared Business credits after signing in to the correct ChatGPT workspace."
        case .restricted:
            "Workspace billing links aren't available from Ammo in this App Store region. A Workspace Owner can manage credits in ChatGPT."
        case .unknown:
            "Ammo couldn't verify the App Store region, so workspace billing stays unavailable."
        }
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
        let presentation = OnDemandUsagePresentation(
            usage: usage,
            referenceDate: referenceDate)
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                usageLabel
                statusBadge
            }

            Text(presentation.primaryText)
                .font(.headline.weight(.semibold).monospacedDigit())
                .foregroundStyle(primaryColor)
                .fixedSize(horizontal: false, vertical: true)

            if let fraction = usage.remainingFraction, usage.isEnabled != false {
                CapsuleBar(fraction: fraction, color: meterColor, height: 8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.detailText)
                Text(presentation.scopeText)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let resetsAt = usage.resetsAt, resetsAt > referenceDate {
                let resetText = OnDemandUsagePresentation.remainingText(
                    until: resetsAt,
                    referenceDate: referenceDate)
                Label {
                    Text("Resets in \(resetText)")
                } icon: {
                    Image(systemName: "arrow.clockwise")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let expiresAt = usage.expiresAt,
               let expirationText = presentation.expirationText {
                Label {
                    Text(expirationText)
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
        Text(OnDemandUsagePresentation(usage: usage, referenceDate: referenceDate).statusText)
            .font(.caption.weight(.medium))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.12), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
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

}

struct OnDemandUsagePresentation: Equatable {
    let primaryText: String
    let detailText: String
    let statusText: String
    let scopeText: String
    let expirationText: String?

    init(usage: OnDemandUsage, referenceDate: Date) {
        if usage.isEnabled == false {
            primaryText = "On-demand is off"
        } else if usage.isUnlimited, let used = usage.used {
            primaryText = "\(Self.amount(used, usage: usage)) used"
        } else if usage.isUnlimited, let remaining = usage.remainingAmount {
            // Unlimited entries with a known balance (Codex usage credits) keep
            // showing that balance instead of reading like a fetch failure.
            primaryText = "\(Self.amount(remaining, usage: usage)) balance"
        } else if usage.isUnlimited {
            primaryText = "Amount unavailable"
        } else if let remaining = usage.remainingAmount {
            primaryText = "\(Self.amount(remaining, usage: usage)) remaining"
        } else if let used = usage.used {
            primaryText = "\(Self.amount(used, usage: usage)) used"
        } else if usage.effectiveUnit == .credits {
            primaryText = "Balance unavailable"
        } else {
            primaryText = "Amount unavailable"
        }

        if usage.isEnabled == false {
            if let limit = usage.limit {
                detailText = "\(Self.amount(limit, usage: usage)) configured limit"
            } else {
                detailText = "Not available for paid continuation"
            }
        } else if let equivalentAmount = usage.equivalentAmount,
                  let code = usage.equivalentCurrencyCode {
            detailText = "\(Self.money(equivalentAmount, currencyCode: code)) equivalent"
        } else if let used = usage.used, let limit = usage.limit {
            detailText = "\(Self.amount(used, usage: usage)) of \(Self.amount(limit, usage: usage)) used"
        } else if usage.kind == .creditBalance {
            detailText = usage.remainingAmount == nil
                ? "Balance not reported to Ammo"
                : "Prepaid usage balance"
        } else if usage.isUnlimited {
            detailText = "No spending limit reported"
        } else if let limit = usage.limit {
            detailText = "\(Self.amount(limit, usage: usage)) limit"
        } else {
            detailText = "Provider-reported capacity"
        }

        if usage.isEnabled == false {
            statusText = "Off"
        } else if usage.isUnlimited {
            statusText = "No limit"
        } else if usage.isExhausted {
            statusText = "Exhausted"
        } else if usage.remainingAmount == nil && usage.effectiveUnit == .credits {
            statusText = "Unavailable"
        } else if (usage.used ?? 0) > 0 {
            statusText = "Active"
        } else {
            statusText = "Ready"
        }

        switch usage.scope {
        case .personal: scopeText = "Personal"
        case .team: scopeText = "Team"
        case .organization: scopeText = "Organization"
        }

        if let expiresAt = usage.expiresAt {
            let remaining = Self.remainingText(
                until: expiresAt,
                referenceDate: referenceDate)
            expirationText = expiresAt > referenceDate
                ? "Expires in \(remaining)"
                : "Expired"
        } else {
            expirationText = nil
        }
    }

    static func remainingText(until date: Date, referenceDate: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(referenceDate)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }

    private static func amount(_ value: Double, usage: OnDemandUsage) -> String {
        if usage.effectiveUnit == .credits {
            return value.formatted(
                .number.grouping(.automatic).precision(.fractionLength(0))) + " credits"
        }
        return money(value, currencyCode: usage.currencyCode)
    }

    private static func money(_ amount: Double, currencyCode: String) -> String {
        amount.formatted(
            .currency(code: currencyCode)
            .precision(.fractionLength(2))
        )
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
        if entry.isUnlimited, let used = entry.used {
            let formatted: String
            if entry.effectiveUnit == .credits {
                formatted = used.formatted(
                    .number.grouping(.automatic).precision(.fractionLength(0))) + " credits"
            } else {
                formatted = used.formatted(
                    .currency(code: entry.currencyCode)
                    .precision(.fractionLength(2)))
            }
            return "On-demand · \(formatted) used · no limit"
        }
        if entry.isUnlimited { return "On-demand · no limit" }
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
