import SwiftUI

@main
struct AmmoApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundRefresh.register() // must happen before launch completes
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AccountStore.shared)
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
