import BackgroundTasks
import Foundation

/// BGAppRefreshTask plumbing. iOS decides the actual cadence from its budget;
/// we ask for no sooner than 30 minutes and re-arm on every run.
enum BackgroundRefresh {
    static let taskID = "com.brandon.ammo.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            nonisolated(unsafe) let task = task
            Task { @MainActor in
                schedule() // keep the chain alive for the next wake
                await AccountStore.shared.refreshAll()
                task.setTaskCompleted(success: true)
            }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        // Errors here are expected (e.g. simulator, task already queued) — the
        // foreground path still refreshes.
        try? BGTaskScheduler.shared.submit(request)
    }
}
