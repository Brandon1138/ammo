import SwiftUI
import UsageKit

enum AppTab: Hashable {
    case usage
    case onDemand
    case history
}

/// Navigation restoration policy for the root tab bar.
///
/// Ammo intentionally does not persist a user's last-selected tab. Every normal
/// scene activation starts from Usage, while an explicit HistoryLink is allowed
/// to select History for the activation that receives it. Keeping this policy in
/// one place prevents SwiftUI or UIKit state restoration from replaying a stale
/// History selection after the user returned to Usage.
enum TabSelectionPolicy {
    static func tabForSceneActivation(
        isInitialActivation: Bool,
        initialTab: AppTab,
        hasPendingHistoryLink: Bool
    ) -> AppTab {
        if hasPendingHistoryLink {
            return .history
        }
        return isInitialActivation ? initialTab : .usage
    }
}

struct ContentView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab
    @State private var historySelection = HistorySelection()
    @State private var hasActivated = false
    @State private var hasPendingHistoryLink = false
    private let initialTab: AppTab

    init() {
#if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        let initialTab: AppTab
        if arguments.contains("--ammo-on-demand-preview")
            || environment["AMMO_ON_DEMAND_PREVIEW"] == "1" {
            initialTab = .onDemand
        } else if arguments.contains("--ammo-history-preview")
            || environment["AMMO_HISTORY_PREVIEW"] == "1" {
            initialTab = .history
        } else {
            initialTab = .usage
        }
#else
        let initialTab: AppTab = .usage
#endif
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Usage", systemImage: "gauge.with.dots.needle.50percent", value: .usage) {
                UsageView(
                    openOnDemand: { selectedTab = .onDemand },
                    openHistory: { accountID, windowID in
                        historySelection = HistorySelection(accountID: accountID, windowID: windowID)
                        selectedTab = .history
                    }
                )
            }
            Tab("On-demand", systemImage: "bolt.fill", value: .onDemand) {
                OnDemandView()
            }
            Tab("History", systemImage: "chart.xyaxis.line", value: .history) {
                HistoryView(selection: $historySelection)
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }

            selectedTab = TabSelectionPolicy.tabForSceneActivation(
                isInitialActivation: !hasActivated,
                initialTab: initialTab,
                hasPendingHistoryLink: hasPendingHistoryLink
            )
            hasActivated = true
            hasPendingHistoryLink = false
        }
        .onOpenURL { url in
#if targetEnvironment(simulator)
            if url.scheme == HistoryLink.scheme, url.host == "preview-history" {
                store.installHistoryPreview()
                return
            }
#endif
            guard let link = HistoryLink(url: url) else { return }
            historySelection = HistorySelection(accountID: link.accountID, windowID: link.windowID)
            if scenePhase == .active {
                selectedTab = .history
            } else {
                hasPendingHistoryLink = true
            }
        }
    }
}

private struct UsageView: View {
    @Environment(AccountStore.self) private var store
    @State private var presentedSheet: UsageSheet?
    let openOnDemand: () -> Void
    let openHistory: (UUID, String) -> Void

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
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("AmmoLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 116, height: 25)
                        .accessibilityLabel("Ammo")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        presentedSheet = .settings
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if store.isDemoMode {
                        Button("Exit Demo") { store.disableDemoMode() }
                    } else {
                        Menu {
                            Button {
                                presentedSheet = .addProvider(.claude)
                            } label: {
                                Label {
                                    Text("Claude")
                                } icon: {
                                    ProviderLogo(provider: .claude, size: 16, role: .menu)
                                }
                            }
                            Button {
                                presentedSheet = .addProvider(.codex)
                            } label: {
                                Label {
                                    Text("Codex")
                                } icon: {
                                    ProviderLogo(provider: .codex, size: 16, role: .menu)
                                }
                            }
                            Button {
                                presentedSheet = .addProvider(.cursor)
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
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .settings:
                    SettingsView()
                case .addProvider(let provider):
                    switch provider {
                    case .claude: ClaudeOnboardingView()
                    case .codex: CodexOnboardingView()
                    case .cursor: CursorOnboardingView()
                    case .antigravity: EmptyView() // deferred, see SPEC.md
                    }
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
            Button("Add Claude") { presentedSheet = .addProvider(.claude) }
            Button("Add Codex") { presentedSheet = .addProvider(.codex) }
            Button("Add Cursor") { presentedSheet = .addProvider(.cursor) }
            Button("See a demo") { store.enableDemoMode() }
        }
    }

    private var accountList: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            List {
                ForEach(store.states) { state in
                    AccountSection(state: state,
                                   referenceDate: context.date,
                                   openOnDemand: openOnDemand,
                                   openHistory: openHistory)
                }
            }
            .refreshable {
                await store.refreshAll(reason: .manual)
            }
            .listSectionSpacing(.custom(10))
        }
    }
}

private enum UsageSheet: Identifiable {
    case settings
    case addProvider(ProviderID)

    var id: String {
        switch self {
        case .settings:
            "settings"
        case .addProvider(let provider):
            "add-\(provider.rawValue)"
        }
    }
}

private struct AccountSection: View {
    @Environment(AccountStore.self) private var store
    let state: AccountState
    let referenceDate: Date
    let openOnDemand: () -> Void
    let openHistory: (UUID, String) -> Void

    var body: some View {
        Group {
            Section {
                if let snapshot = state.snapshot {
                    ForEach(snapshot.windowGroups, id: \.first!.id) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(group) { window in
                                Button {
                                    openHistory(state.id, window.id)
                                } label: {
                                    UsageWindowRow(window: window,
                                                   font: .subheadline,
                                                   barHeight: 8)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Shows usage history")
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
                    if snapshot.onDemand?.isEmpty == false {
                        OnDemandSummaryButton(snapshot: snapshot, action: openOnDemand)
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                    if store.isDemoMode {
                        Text("Sample data")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .textCase(nil)
                    }
                    if let plan = state.snapshot?.displayPlan {
                        Text(plan)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .textCase(nil)
                    }
                    Spacer()
                    if !store.isDemoMode {
                        Menu {
                            Button("Remove Account", systemImage: "trash", role: .destructive) {
                                store.remove(state.account)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
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
                        hasCachedSnapshot: state.snapshot != nil,
                        retryState: store.retryState(for: state.id,
                                                     at: referenceDate)) {
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
