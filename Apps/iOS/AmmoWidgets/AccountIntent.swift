import AppIntents
import WidgetKit

/// Widget-configurable account choice. Entities are hydrated from the App
/// Group snapshot file — the widget process never touches the Keychain.
struct AccountEntity: AppEntity {
    let id: UUID
    let label: String
    let providerName: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = AccountQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)", subtitle: "\(providerName)")
    }

    init(state: AccountState) {
        id = state.account.id
        label = state.account.label
        providerName = state.account.provider.displayName
    }
}

struct AccountQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        SharedStore.load()
            .filter { identifiers.contains($0.account.id) }
            .map(AccountEntity.init)
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        SharedStore.load().map(AccountEntity.init)
    }

    func defaultResult() async -> AccountEntity? {
        SharedStore.load().first.map(AccountEntity.init)
    }
}

struct SelectAccountIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Account"
    static let description = IntentDescription("Choose which account this widget shows.")

    @Parameter(title: "Account")
    var account: AccountEntity?
}
