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

                if SnapshotPrivacyPolicy.shieldsContent(in: scenePhase) {
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

/// Decides when rendered credentials have to be covered.
///
/// iOS takes the app-switcher snapshot *after* the scene reaches `.background`,
/// so that is the only phase the shield has to cover. `.inactive` merely means a
/// system gesture is in flight — a Notification Centre or Control Centre pull, an
/// alert, a call banner — while the app is still on screen and no snapshot is
/// pending. Shielding there blanked Ammo from the first pixel of the pull and
/// through the whole cancel/restore (MIK-146).
enum SnapshotPrivacyPolicy {
    static func shieldsContent(in phase: ScenePhase) -> Bool {
        phase == .background
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
