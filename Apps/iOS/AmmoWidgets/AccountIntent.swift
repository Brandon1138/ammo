import AppIntents
import UsageKit
import WidgetKit

/// Widget-configurable account choice. Entities are hydrated from the App
/// Group snapshot file — the widget process never touches the Keychain.
struct AccountEntity: AppEntity {
    let id: UUID
    let label: String
    let detail: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = AccountQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)", subtitle: "\(detail)")
    }

    init(state: AccountState) {
        id = state.account.id
        label = state.account.label
        detail = if let plan = state.snapshot?.displayPlan {
            "\(state.account.provider.displayName) · \(plan)"
        } else {
            state.account.provider.displayName
        }
    }
}

struct AccountQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        SharedStore.load()
            .filter { identifiers.contains($0.account.id) }
            .map(AccountEntity.init)
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        WidgetAccountOrder.defaultOrder(SharedStore.load()).map(AccountEntity.init)
    }

    func defaultResult() async -> AccountEntity? {
        WidgetAccountOrder.defaultOrder(SharedStore.load()).first.map(AccountEntity.init)
    }
}

struct SelectAccountIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Account"
    static let description = IntentDescription("Choose which account this widget shows.")

    @Parameter(title: "Account")
    var account: AccountEntity?
}

/// Ordered account slots for the multi-account widget. Explicit slots keep the
/// user's order deterministic across widget sizes and avoid depending on the
/// system's ordering of a multi-select entity parameter.
struct SelectAccountsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Accounts"
    static let description = IntentDescription("Choose which accounts appear and their order.")

    @Parameter(title: "First Account")
    var firstAccount: AccountEntity?

    @Parameter(title: "Second Account")
    var secondAccount: AccountEntity?

    @Parameter(title: "Third Account")
    var thirdAccount: AccountEntity?

    @Parameter(title: "Fourth Account")
    var fourthAccount: AccountEntity?

    var orderedAccountIDs: [UUID] {
        var seen = Set<UUID>()
        return [firstAccount, secondAccount, thirdAccount, fourthAccount]
            .compactMap { $0?.id }
            .filter { seen.insert($0).inserted }
    }
}

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
        case .antigravity: 3
        }
    }
}

/// A single account plus allowance, kept as one picker entity so widget
/// configuration never permits an account/window mismatch.
struct LimitEntity: AppEntity {
    let id: String
    let accountID: UUID
    let windowID: String
    let accountLabel: String
    let windowLabel: String
    let providerName: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Usage Limit"
    static let defaultQuery = LimitQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(accountLabel) · \(windowLabel)",
            subtitle: "\(providerName)"
        )
    }

    init(state: AccountState, window: LimitWindow) {
        id = "\(state.id.uuidString)|\(window.id)"
        accountID = state.id
        windowID = window.id
        accountLabel = state.account.label
        windowLabel = window.label
        providerName = state.account.provider.displayName
    }
}

struct LimitQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LimitEntity] {
        Self.allLimits().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [LimitEntity] {
        Self.allLimits()
    }

    func defaultResult() async -> LimitEntity? {
        let states = WidgetAccountOrder.defaultOrder(SharedStore.load())
        for state in states {
            guard let window = Self.preferredWindow(in: state.snapshot?.windows ?? []) else { continue }
            return LimitEntity(state: state, window: window)
        }
        return nil
    }

    private static func allLimits() -> [LimitEntity] {
        WidgetAccountOrder.defaultOrder(SharedStore.load()).flatMap { state in
            (state.snapshot?.windows ?? []).map { LimitEntity(state: state, window: $0) }
        }
    }

    static func preferredWindow(in windows: [LimitWindow]) -> LimitWindow? {
        windows.first(where: { $0.kind == .weekly })
            ?? windows.first(where: { $0.kind == .monthly })
            ?? windows.first
    }
}

struct SelectLimitIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Activity"
    static let description = IntentDescription("Choose which account and usage limit this widget shows.")

    @Parameter(title: "Usage Limit")
    var limit: LimitEntity?
}
