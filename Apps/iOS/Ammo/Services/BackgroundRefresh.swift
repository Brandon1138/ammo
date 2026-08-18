import BackgroundTasks
import Foundation
import UsageKit

/// BGAppRefreshTask plumbing. iOS decides the actual cadence from its budget;
/// we adapt the requested date to remaining usage and known reset times.
enum BackgroundRefresh {
    static let taskID = "com.brandon.ammo.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            handle(task)
        }
    }

    /// iOS scores future budget on what we report here, so the outcome has to be
    /// the real one: a run in which every account failed is not a success, and a
    /// run iOS expires before we finish did not complete at all.
    static func handle(_ task: BGTask) {
        nonisolated(unsafe) let task = task
        let completion = CompletionLatch()
        // Re-arm before provider work. Nothing should enqueue new background
        // work after iOS expires this task.
        schedule()
        let work = Task { @MainActor in
            let outcomes = await AccountStore.shared.refreshAll(reason: .background)
            guard !Task.isCancelled, completion.claim() else { return }
            let success = didSucceed(outcomes: outcomes)
            if !success {
                AmmoLog.refresh.error("Background refresh finished with no successful account")
            }
            WidgetInvalidator.shared.flushPendingBeforeSuspension()
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = {
            work.cancel()
            guard completion.claim() else { return }
            AmmoLog.refresh.error("Background refresh expired before it finished")
            WidgetInvalidator.shared.flushPendingBeforeSuspension()
            task.setTaskCompleted(success: false)
        }
    }

    /// A refresh run is a success when at least one account produced usable
    /// state — a fresh snapshot, or a cached one the throttle deliberately kept.
    /// No accounts is vacuously fine; there was nothing to fetch.
    static func didSucceed(outcomes: [RefreshOutcome]) -> Bool {
        guard !outcomes.isEmpty else { return true }
        return outcomes.contains { outcome in
            switch outcome {
            case .refreshed, .cached: true
            case .failed: false
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

/// `BGTask.setTaskCompleted` must be called exactly once. The expiration handler
/// runs on an arbitrary queue and races the refresh, so completion is latched.
final class CompletionLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var isClaimed = false

    /// True for the first caller only.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isClaimed { return false }
        isClaimed = true
        return true
    }
}
