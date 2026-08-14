import SwiftUI

@main
struct AmmoApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundRefresh.register() // must happen before launch completes
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(AccountStore.shared)

                if scenePhase != .active {
                    SnapshotPrivacyShield()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await AccountStore.shared.refreshAll(reason: .foreground) }
            case .background:
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
    }
}

/// Covers rendered credentials before iOS captures app-switcher snapshots.
private struct SnapshotPrivacyShield: View {
    var body: some View {
        Color(uiColor: .systemBackground)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
