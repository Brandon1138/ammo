import SwiftUI
import UsageKit

/// Every sheet a tab presents from its shared header, plus the two sheets Usage
/// and History raise from their own content. They share one route so a tab owns
/// exactly one `.sheet` presentation instead of stacking modifiers.
enum AmmoTabSheet: Identifiable {
    case settings
    case reorder
    case addProvider(ProviderID)
    /// Re-runs the provider's add flow against an account that already exists.
    case reconnect(StoredAccount)

    var id: String {
        switch self {
        case .settings:
            "settings"
        case .reorder:
            "reorder"
        case .addProvider(let provider):
            "add-\(provider.rawValue)"
        case .reconnect(let account):
            "reconnect-\(account.id.uuidString)"
        }
    }
}

/// What the trailing header button does. Demo mode replaces Add Account with the
/// way back out of the demo, and it does so on every tab.
enum AmmoHeaderTrailingAction: Equatable {
    case addAccount
    case exitDemo

    static func resolve(isDemoMode: Bool) -> AmmoHeaderTrailingAction {
        isDemoMode ? .exitDemo : .addAccount
    }
}

/// Ammo's compact top chrome: Settings gear leading, Ammo logo centred, Add
/// Account trailing. Usage, On-demand, and History all draw this one bar, so
/// none of them carries a large typed navigation title.
struct AmmoTabToolbar: ToolbarContent {
    let isDemoMode: Bool
    let exitDemo: () -> Void
    let present: (AmmoTabSheet) -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Image("AmmoLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 116, height: 25)
                .accessibilityLabel("Ammo")
        }
        ToolbarItem(placement: .topBarLeading) {
            Button {
                present(.settings)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            switch AmmoHeaderTrailingAction.resolve(isDemoMode: isDemoMode) {
            case .exitDemo:
                Button("Exit Demo", action: exitDemo)
            case .addAccount:
                Menu {
                    ForEach(ProviderID.supported) { provider in
                        Button {
                            present(.addProvider(provider))
                        } label: {
                            Label {
                                Text(provider.displayName)
                            } icon: {
                                ProviderLogo(provider: provider, size: 16, role: .menu)
                            }
                        }
                    }
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
            }
        }
    }
}

private struct AmmoTabHeaderModifier: ViewModifier {
    @Environment(AccountStore.self) private var store
    @Binding var sheet: AmmoTabSheet?

    func body(content: Content) -> some View {
        content
            .navigationTitle("Ammo")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                AmmoTabToolbar(
                    isDemoMode: store.isDemoMode,
                    exitDemo: { store.disableDemoMode() },
                    present: { sheet = $0 })
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .settings:
                    SettingsView()
                case .reorder:
                    ReorderAccountsView()
                case .addProvider(let provider):
                    ProviderSignInSheet(provider: provider)
                case .reconnect(let account):
                    ProviderSignInSheet(provider: account.provider, reconnecting: account)
                }
            }
    }
}

extension View {
    /// Applies Ammo's shared compact top chrome and the sheet routing behind it.
    /// The caller owns the selection so its own content can raise a sheet too.
    func ammoTabHeader(sheet: Binding<AmmoTabSheet?>) -> some View {
        modifier(AmmoTabHeaderModifier(sheet: sheet))
    }
}
