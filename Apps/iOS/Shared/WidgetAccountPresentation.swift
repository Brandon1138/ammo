import Foundation
import UsageKit
import WidgetKit

/// Provider-neutral ordering shared by widget configuration and tests.
///
/// The person's own order is the primary key: an account they placed outranks
/// every account they did not, whatever its usage data looks like. The old
/// completeness heuristics survive only as the tiebreak *between* accounts with
/// no explicit position, so a store with no stored order behaves exactly as it
/// did before the preference existed. Accounts with honest amount-only data
/// remain selectable even without percentage windows.
enum WidgetAccountOrder {
    static func defaultOrder(
        _ states: [AccountState],
        order: AccountOrder = AccountOrderStore.load()
    ) -> [AccountState] {
        order.arranged(states, id: \.id, tiebreak: heuristicPrecedes)
    }

    /// The pre-MIK-157 ordering, now reached only for accounts the person has
    /// never placed.
    private static func heuristicPrecedes(_ lhs: AccountState, _ rhs: AccountState) -> Bool {
        let leftRank = availabilityRank(lhs)
        let rightRank = availabilityRank(rhs)
        if leftRank != rightRank { return leftRank < rightRank }

        let leftProvider = providerRank(lhs.account.provider)
        let rightProvider = providerRank(rhs.account.provider)
        if leftProvider != rightProvider { return leftProvider < rightProvider }

        return lhs.account.label.localizedCaseInsensitiveCompare(rhs.account.label) == .orderedAscending
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
    static let allProviders: [ProviderID] = [.codex, .claude, .cursor, .openRouter]

    /// Four shipping providers always occupy the board.
    static var providers: [ProviderID] { allProviders }

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
    /// the person's top-ranked account of that provider takes the slot; the
    /// most-complete-usage heuristic decides only when they have placed none of
    /// them. The order is read once here rather than per provider so all four
    /// panels are resolved against the same stored list.
    static func slots(
        states: [AccountState],
        order: AccountOrder = AccountOrderStore.load()
    ) -> [WidgetProviderSlot] {
        providers.map { provider in
            let candidates = states.filter { $0.account.provider == provider }
            return WidgetProviderSlot(
                provider: provider,
                state: WidgetAccountOrder.defaultOrder(candidates, order: order).first)
        }
    }
}

extension AccountState {
    var widgetPercentageWindow: LimitWindow? { snapshot?.worstWindow }

    /// Lock Screen gauge uses the shared neutral window selection.
    var lockScreenUsagePresentation: LockScreenUsagePresentation? {
        snapshot.flatMap(LockScreenUsagePresentation.init(snapshot:))
    }

    /// Lock Screen gauge for an account whose provider reported spend but no
    /// percentage window. Cursor reaches this whenever `usage-summary` omits the
    /// `individualUsage.plan` block — team and enterprise members, and
    /// usage-based plans — and OpenRouter reaches it always. Percentage windows
    /// still win: this is only consulted when `lockScreenUsagePresentation` is
    /// nil.
    var lockScreenMeteredPresentation: MeteredLockScreenPresentation? {
        snapshot.flatMap(MeteredLockScreenPresentation.init(snapshot:))
    }

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

    var widgetAvailabilityText: String {
        if snapshot?.onDemand?.isEmpty == false { return "Metered usage only" }
        return activeFailure == nil ? "No usage limits yet" : "Update paused — open Ammo"
    }

    var widgetCompactAvailabilityText: String {
        if snapshot?.onDemand?.isEmpty == false { return "Metered" }
        return activeFailure == nil ? "No limits" : "Paused"
    }
}
