import SwiftUI
import UsageKit

enum AppTab: Hashable {
    case usage
    case onDemand
    case history
}

/// Synchronous navigation state for the root tab bar.
///
/// Ammo intentionally does not persist a user's last-selected tab. Every normal
/// foreground is prepared as Usage while the scene is hidden, so SwiftUI never
/// needs to correct a stale History selection after drawing the active scene.
/// Explicit History links update the selection before activation and take
/// priority over that normal reset.
struct TabSelectionState {
    private(set) var selectedTab: AppTab
    private var hasActivated = false
    private var hasPendingHistoryLink = false

    init(initialTab: AppTab) {
        selectedTab = initialTab
    }

    mutating func select(_ tab: AppTab) {
        selectedTab = tab
    }

    mutating func sceneDidBecomeActive() {
        hasActivated = true
        if hasPendingHistoryLink {
            selectedTab = .history
            hasPendingHistoryLink = false
        }
    }

    mutating func sceneDidEnterBackground() {
        guard hasActivated, !hasPendingHistoryLink else { return }
        selectedTab = .usage
    }

    mutating func scenePhaseChanged(to phase: ScenePhase) {
        switch phase {
        case .active:
            sceneDidBecomeActive()
        case .background:
            sceneDidEnterBackground()
        case .inactive:
            // Short interruptions such as Control Center can leave the app
            // visible. Preserve the selected tab until the scene is hidden.
            break
        @unknown default:
            break
        }
    }

    mutating func openHistory(isSceneActive: Bool) {
        selectedTab = .history
        hasPendingHistoryLink = !isSceneActive
    }
}

struct ContentView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tabSelection: TabSelectionState
    @State private var historySelection = HistorySelection()

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
        _tabSelection = State(initialValue: TabSelectionState(initialTab: initialTab))
    }

    var body: some View {
        TabView(selection: Binding(
            get: { tabSelection.selectedTab },
            set: { tabSelection.select($0) }
        )) {
            Tab("Usage", systemImage: "gauge.with.dots.needle.50percent", value: .usage) {
                UsageView(
                    openOnDemand: { tabSelection.select(.onDemand) },
                    openHistory: { accountID, windowID in
                        historySelection = HistorySelection(accountID: accountID, windowID: windowID)
                        tabSelection.select(.history)
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
            tabSelection.scenePhaseChanged(to: phase)
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
            tabSelection.openHistory(isSceneActive: scenePhase == .active)
        }
    }
}

private struct UsageView: View {
    @Environment(AccountStore.self) private var store
    @State private var presentedSheet: AmmoTabSheet?
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
            .ammoTabHeader(sheet: $presentedSheet)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No accounts yet", systemImage: "battery.0percent")
        } description: {
            Text("Add a Claude, Codex, Cursor, or OpenRouter account to see how much ammo you have left.")
        } actions: {
            ForEach(ProviderID.supported) { provider in
                Button("Add \(provider.displayName)") {
                    presentedSheet = .addProvider(provider)
                }
            }
            Button("See a demo") { store.enableDemoMode() }
        }
    }

    private var accountList: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            List {
                if let notice = store.signInNotice {
                    Section {
                        Label(notice, systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .task(id: notice) {
                                try? await Task.sleep(for: .seconds(6))
                                store.clearSignInNotice()
                            }
                    }
                }
                ForEach(store.states) { state in
                    AccountSection(state: state,
                                   referenceDate: context.date,
                                   openOnDemand: openOnDemand,
                                   openHistory: openHistory,
                                   reconnect: { presentedSheet = .reconnect($0) },
                                   openReorder: { presentedSheet = .reorder })
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
    @State private var isConfirmingRemoval = false
    let state: AccountState
    let referenceDate: Date
    let openOnDemand: () -> Void
    let openHistory: (UUID, String) -> Void
    let reconnect: (StoredAccount) -> Void
    let openReorder: () -> Void

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
                            // Repairs an expired provider session under the same
                            // account id, so history and widgets stay attached.
                            Button("Sign In Again", systemImage: "person.badge.key") {
                                reconnect(state.account)
                            }
                            if store.canReorderAccounts {
                                Button("Reorder Accounts", systemImage: "arrow.up.arrow.down",
                                       action: openReorder)
                            }
                            Button("Remove Account", systemImage: "trash", role: .destructive) {
                                isConfirmingRemoval = true
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
                                                     at: referenceDate),
                        retry: {
                            Task {
                                await store.refresh(ids: [state.id], reason: .manual)
                            }
                        },
                        reconnect: { reconnect(state.account) })
                        .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } footer: {
                    updatedFooter
                }
            }
        }
        .alert(AccountRemovalCopy.title(for: state.account),
               isPresented: $isConfirmingRemoval) {
            Button(AccountRemovalCopy.action, role: .destructive) {
                store.remove(state.account)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(AccountRemovalCopy.message(for: state.account))
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
