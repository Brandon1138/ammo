import SwiftUI
import UsageKit

struct ContentView: View {
    @Environment(AccountStore.self) private var store
    @State private var addingProvider: ProviderID?

    var body: some View {
        NavigationStack {
            Group {
                if store.states.isEmpty {
                    emptyState
                } else {
                    accountList
                }
            }
            .navigationTitle("Ammo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Claude", systemImage: ProviderID.claude.symbolName) {
                            addingProvider = .claude
                        }
                        Button("Codex", systemImage: ProviderID.codex.symbolName) {
                            addingProvider = .codex
                        }
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $addingProvider) { provider in
                switch provider {
                case .claude: ClaudeOnboardingView()
                case .codex: CodexOnboardingView()
                case .cursor, .antigravity: EmptyView() // deferred, see SPEC.md
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No accounts yet", systemImage: "battery.0percent")
        } description: {
            Text("Add a Claude or Codex account to see how much ammo you have left.")
        } actions: {
            Button("Add Claude") { addingProvider = .claude }
            Button("Add Codex") { addingProvider = .codex }
        }
    }

    private var accountList: some View {
        List {
            ForEach(store.states) { state in
                AccountSection(state: state)
            }
        }
        .refreshable {
            await store.refreshAll()
        }
    }
}

private struct AccountSection: View {
    @Environment(AccountStore.self) private var store
    let state: AccountState

    var body: some View {
        Section {
            if let snapshot = state.snapshot {
                ForEach(snapshot.windows) { window in
                    WindowRow(window: window)
                }
                if let credits = snapshot.resetCreditsAvailable, credits > 0 {
                    Label("\(credits) reset\(credits == 1 ? "" : "s") available",
                          systemImage: "arrow.clockwise.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if state.lastError == nil {
                HStack {
                    ProgressView()
                    Text("Fetching…").foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Label(state.account.label, systemImage: state.account.provider.symbolName)
                if let plan = state.snapshot?.plan {
                    Text(plan.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                Menu {
                    Button("Remove Account", systemImage: "trash", role: .destructive) {
                        store.remove(state.account)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let error = state.lastError {
                    Text(error).foregroundStyle(.red)
                }
                if let updatedAt = state.updatedAt {
                    Text("Updated \(Text(updatedAt, style: .relative)) ago")
                }
            }
        }
    }
}

private struct WindowRow: View {
    let window: LimitWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(window.label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))% left")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(window.barColor)
            }
            ProgressView(value: window.remainingPercent, total: 100)
                .tint(window.barColor)
            if let resetsAt = window.resetsAt, resetsAt > Date() {
                Text("Resets in \(Text(resetsAt, style: .relative))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
