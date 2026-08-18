import Foundation
import UsageKit
import WidgetKit

/// Provider-neutral ordering shared by widget configuration and tests. Accounts
/// with honest amount-only data remain selectable even without percentage windows.
enum WidgetAccountOrder {
    static func defaultOrder(_ states: [AccountState]) -> [AccountState] {
        states.sorted { lhs, rhs in
            let leftRank = availabilityRank(lhs)
            let rightRank = availabilityRank(rhs)
            if leftRank != rightRank { return leftRank < rightRank }

            let leftProvider = providerRank(lhs.account.provider)
            let rightProvider = providerRank(rhs.account.provider)
            if leftProvider != rightProvider { return leftProvider < rightProvider }

            return lhs.account.label.localizedCaseInsensitiveCompare(rhs.account.label) == .orderedAscending
        }
    }

    private static func availabilityRank(_ state: AccountState) -> Int {
        guard let snapshot = state.snapshot else {
            return state.activeFailure == nil ? 3 : 4
        }
        if !snapshot.windows.isEmpty { return 0 }
        if snapshot.onDemand?.isEmpty == false { return 1 }
        return 2
    }

    private static func providerRank(_ provider: ProviderID) -> Int {
        switch provider {
        case .codex: 0
        case .claude: 1
        case .cursor: 2
        case .openRouter: 3
        case .antigravity: 4
        }
    }
}

/// One panel of the provider board: a shipping provider and the account backing
/// it, if the widget was given one. The provider is always present so a missing
/// account renders an explicit slot instead of a gap.
struct WidgetProviderSlot: Identifiable {
    let provider: ProviderID
    let state: AccountState?

    var id: String { provider.rawValue }
}

enum WidgetProviderPanels {
    /// Fixed panel order, matching the provider ranking used by the default
    /// account ordering so the board does not move between refreshes.
    static let providers: [ProviderID] = [.codex, .claude, .cursor, .openRouter]

    /// Families the Accounts widget offers. The board is drawn in
    /// `systemExtraLargePortrait`, the tall portrait family iOS 27 added to the
    /// iPhone Home Screen (`@available(iOS 27.0, macOS 27.0, visionOS 26.0, *)`
    /// in the iPhoneOS 27.0 SDK's `WidgetKit.swiftinterface`) — one grid width by
    /// six rows, so roughly one and a half `systemLarge` heights. The landscape
    /// `systemExtraLarge` family is deliberately absent: it is iPad and Mac only
    /// and Ammo ships `TARGETED_DEVICE_FAMILY = 1`, so declaring it only produced
    /// a family nothing could ever install.
    static var accountsFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
        if #available(iOS 27.0, *) {
            families.append(.systemExtraLargePortrait)
        }
        return families
    }

    /// Whether `family` is the tall board. Kept here rather than compared inline
    /// so the availability gate exists once for both the timeline provider and
    /// the view.
    static func isProviderBoard(_ family: WidgetFamily) -> Bool {
        guard #available(iOS 27.0, *) else { return false }
        return family == .systemExtraLargePortrait
    }

    /// Three windows preserve Claude's Session, Weekly, and provider-reported
    /// model bucket (currently Fable) without manufacturing a row on plans that
    /// omit it. Other providers naturally collapse to their shorter lists.
    static let boardWindowLimit = 3

    /// One slot per shipping provider. Where several accounts share a provider,
    /// the default ordering picks the one with the most complete usage data.
    static func slots(states: [AccountState]) -> [WidgetProviderSlot] {
        providers.map { provider in
            let candidates = states.filter { $0.account.provider == provider }
            return WidgetProviderSlot(
                provider: provider,
                state: WidgetAccountOrder.defaultOrder(candidates).first)
        }
    }
}

extension AccountState {
    var widgetPercentageWindow: LimitWindow? { snapshot?.worstWindow }

    /// Optional provider-reported model buckets, Fable first and otherwise in
    /// payload order. Empty means the payload omitted them; compact widgets
    /// reserve no row and invent no placeholder.
    var widgetModelScopedWindows: [LimitWindow] {
        let windows = snapshot?.windows.filter { $0.kind == .modelScoped } ?? []
        // A partition keeps the provider's own ordering intact behind Fable;
        // `sorted` would be free to shuffle the equally-ranked remainder.
        return windows.filter(\.isFableModelWindow)
            + windows.filter { !$0.isFableModelWindow }
    }

    /// The one model bucket a compact surface prints beside its headline meter.
    /// Nil when the payload has no bucket, or when the headline meter already
    /// is that bucket — the same window must never be drawn twice.
    var widgetCompactModelWindow: LimitWindow? {
        guard let window = widgetModelScopedWindows.first else { return nil }
        return window.id == widgetPercentageWindow?.id ? nil : window
    }

    var hasWidgetMeteredUsage: Bool {
        snapshot?.onDemand?.contains { $0.isEnabled != false && $0.used != nil } == true
    }

    /// Failure and staleness marker for widget surfaces that draw no percentage
    /// gauge. Metered-only accounts must not silently present cached spending as
    /// if it were current.
    func widgetStatusSymbol(at referenceDate: Date) -> String? {
        if activeFailure != nil { return "exclamationmark.circle.fill" }
        guard let fetchedAt = snapshot?.fetchedAt else { return nil }
        let isStale = referenceDate.timeIntervalSince(fetchedAt)
            > LockScreenUsagePresentation.staleAfter
        return isStale ? "clock.badge.exclamationmark" : nil
    }

    var widgetAvailabilityText: String {
        if snapshot?.onDemand?.isEmpty == false { return "Metered usage only" }
        return activeFailure == nil ? "No usage limits yet" : "Update paused — open Ammo"
    }

    var widgetCompactAvailabilityText: String {
        if snapshot?.onDemand?.isEmpty == false { return "Metered" }
        return activeFailure == nil ? "No limits" : "Paused"
    }
}
