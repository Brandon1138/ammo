import Foundation
import UsageKit

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

extension AccountState {
    var widgetPercentageWindow: LimitWindow? { snapshot?.worstWindow }

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
