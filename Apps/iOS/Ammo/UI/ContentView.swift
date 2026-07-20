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
                        Button {
                            addingProvider = .claude
                        } label: {
                            Label {
                                Text("Claude")
                            } icon: {
                                ProviderLogo(provider: .claude, size: 16, role: .menu)
                            }
                        }
                        Button {
                            addingProvider = .codex
                        } label: {
                            Label {
                                Text("Codex")
                            } icon: {
                                ProviderLogo(provider: .codex, size: 16, role: .menu)
                            }
                        }
                        Button {
                            addingProvider = .cursor
                        } label: {
                            Label {
                                Text("Cursor")
                            } icon: {
                                ProviderLogo(provider: .cursor, size: 16, role: .menu)
                            }
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
                case .cursor: CursorOnboardingView()
                case .antigravity: EmptyView() // deferred, see SPEC.md
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No accounts yet", systemImage: "battery.0percent")
        } description: {
            Text("Add a Claude, Codex, or Cursor account to see how much ammo you have left.")
        } actions: {
            Button("Add Claude") { addingProvider = .claude }
            Button("Add Codex") { addingProvider = .codex }
            Button("Add Cursor") { addingProvider = .cursor }
        }
    }

    private var accountList: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            List {
                ForEach(store.states) { state in
                    AccountSection(state: state, referenceDate: context.date)
                }
            }
            .refreshable {
                await store.refreshAll(reason: .manual)
            }
            .listSectionSpacing(.custom(10))
        }
    }
}

private struct AccountSection: View {
    @Environment(AccountStore.self) private var store
    let state: AccountState
    let referenceDate: Date

    var body: some View {
        Group {
            Section {
                if let snapshot = state.snapshot {
                    ForEach(snapshot.windowGroups, id: \.first!.id) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(group) { window in
                                UsageWindowRow(window: window, font: .subheadline, barHeight: 8)
                            }
                            ResetStatusLine(snapshot: snapshot,
                                            group: group,
                                            referenceDate: referenceDate,
                                            font: .footnote)
                        }
                        .padding(.vertical, 4)
                    }
                    if let credits = snapshot.resetCreditsAvailable, credits > 0 {
                        Label("\(credits) reset\(credits == 1 ? "" : "s") available",
                              systemImage: "arrow.clockwise.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if state.activeFailure == nil {
                    HStack {
                        ProgressView()
                        Text("Fetching…").foregroundStyle(.secondary)
                    }
                }
            } header: {
                HStack(spacing: 7) {
                    ProviderLogo(provider: state.account.provider, size: 20)
                    Text(state.account.label)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                    if let plan = state.snapshot?.plan {
                        Text(plan.capitalized)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .textCase(nil)
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
                .padding(.bottom, 2)
            } footer: {
                if state.activeFailure == nil {
                    updatedFooter
                }
            }

            if let failure = state.activeFailure {
                Section {
                    RefreshIssueNotice(
                        providerName: state.account.provider.displayName,
                        failure: failure,
                        hasCachedSnapshot: state.snapshot != nil) {
                            Task {
                                await store.refresh(ids: [state.id], reason: .manual)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } footer: {
                    updatedFooter
                }
            }
        }
    }

    @ViewBuilder
    private var updatedFooter: some View {
        if let updatedAt = state.updatedAt {
            Text("Updated \(Text(updatedAt, style: .relative)) ago")
                .textCase(nil)
        }
    }
}
