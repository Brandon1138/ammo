import SwiftUI
import UsageKit

/// Drag-to-reorder for the account list.
///
/// A dedicated screen rather than an `onMove` on the Usage list itself: each
/// account there is a `Section` (two, once a refresh issue is showing), and a
/// `List` reorders rows, not sections. Lifting the accounts into a plain row
/// list is what makes the drag well-defined, and it is the same shape iOS uses
/// wherever a sectioned list needs reordering.
///
/// Edit mode is pinned active so the grabbers are visible the moment the sheet
/// opens — the screen exists for nothing else.
struct ReorderAccountsView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.states) { state in
                        AccountOrderRow(account: state.account)
                    }
                    .onMove { source, destination in
                        store.moveAccounts(fromOffsets: source, toOffset: destination)
                    }
                } footer: {
                    Text("Drag accounts into the order you want. Widgets use the same order, and a provider's panel on the board shows the highest account you placed for it.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct AccountOrderRow: View {
    let account: StoredAccount

    var body: some View {
        HStack(spacing: 10) {
            ProviderLogo(provider: account.provider, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.label)
                    .font(.subheadline.weight(.medium))
                if account.label != account.provider.displayName {
                    Text(account.provider.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
