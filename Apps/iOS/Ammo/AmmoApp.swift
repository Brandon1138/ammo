import SwiftUI

@main
struct AmmoApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ForegroundNotificationDelegate.shared.install()
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
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                WidgetInvalidator.shared.resumeAfterSuspension()
                // Republish the cache first so a widget placed while the app was
                // closed leaves its placeholder now, not after the slowest
                // provider answers — or never, when the device is offline.
                AccountStore.shared.invalidateWidgetsFromCache()
                Task {
                    await AccountStore.shared.refreshAll(reason: .foreground)
                    if scenePhase != .active {
                        WidgetInvalidator.shared.flushPendingBeforeSuspension()
                    }
                }
            case .background:
                WidgetInvalidator.shared.flushPendingBeforeSuspension()
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
