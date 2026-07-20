import BackgroundTasks
import Foundation
import UsageKit

/// BGAppRefreshTask plumbing. iOS decides the actual cadence from its budget;
/// we adapt the requested date to remaining usage and known reset times.
enum BackgroundRefresh {
    static let taskID = "com.brandon.ammo.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            nonisolated(unsafe) let task = task
            Task { @MainActor in
                await AccountStore.shared.refreshAll(reason: .background)
                schedule() // re-arm using the newly committed snapshots
                task.setTaskCompleted(success: true)
            }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = RefreshLedgerStore.nextRefreshDate(states: SharedStore.load())
        // Errors here are expected (e.g. simulator, task already queued) — the
        // foreground path still refreshes.
        try? BGTaskScheduler.shared.submit(request)
    }
}
