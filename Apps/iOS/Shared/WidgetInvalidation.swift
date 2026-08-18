import Foundation
import UsageKit
import WidgetKit

/// Why a widget reload was requested. Recorded in the diagnostic log so a stale
/// widget can be traced back to the write that should have invalidated it.
enum WidgetInvalidationReason: String, Sendable {
    case cacheCommitted
    case accountAdded
    case accountRemoved
    case demoModeChanged
    case appForeground
    case refreshFinished
}

/// The one place that asks WidgetKit to rebuild timelines.
///
/// Two properties matter and neither is free:
///
/// 1. **Ordering.** A reload requested before the App Group write lands makes
///    WidgetKit re-read the old bytes, which is indistinguishable from never
///    reloading at all. Every caller therefore invalidates *after* its atomic
///    write has been committed, and `SharedStore` — the only writer — does it
///    itself so a new call site cannot forget.
/// 2. **Budget.** WidgetKit meters reloads per widget per day. A four-account
///    foreground refresh commits four snapshots; four `reloadAllTimelines()`
///    calls for one user-visible change would spend the budget that later
///    refreshes need. Requests are coalesced into a leading call plus at most
///    one trailing call per window.
final class WidgetInvalidator: @unchecked Sendable {
    static let shared = WidgetInvalidator()

    /// Minimum spacing between reload requests actually handed to WidgetKit.
    static let coalescingWindow: TimeInterval = 1.5

    /// Test seam. When set, replaces the WidgetKit call so reload *dispatch*
    /// can be asserted in a unit test without a running widget host.
    private var dispatchOverride: (@Sendable (WidgetInvalidationReason) -> Void)?
    /// Test seam for retaining a trailing work item until its generation can
    /// be invalidated deterministically.
    private var schedulingOverride: (@Sendable (DispatchWorkItem) -> Void)?

    private let lock = NSLock()
    private var lastDispatchUptime: UInt64?
    private var pendingReason: WidgetInvalidationReason?
    /// Identifies the currently armed trailing dispatch. Immediate dispatches
    /// and test resets advance it so a delayed closure cannot mutate newer
    /// coalescing state or spend another WidgetKit reload.
    private var generation: UInt64 = 0

    private init() {}

    /// The widget extension must never ask for its own reload: it has nothing
    /// newer to publish, and the request would spend the shared budget from the
    /// process that can least afford it.
    static var isWidgetProcess: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    func invalidate(
        reason: WidgetInvalidationReason,
        revision: SharedStoreRevision? = nil,
        nowUptime: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        guard !Self.isWidgetProcess else {
            AmmoLog.widgetInvalidation.debug(
                "Skipping reload request from the widget process (\(reason.rawValue, privacy: .public))")
            return
        }

        let shouldDispatchNow: Bool
        let delay: TimeInterval
        let scheduledGeneration: UInt64?
        lock.lock()
        delay = Self.coalescingDelay(
            lastDispatchUptime: lastDispatchUptime,
            nowUptime: nowUptime)
        if lastDispatchUptime != nil, delay > 0 {
            shouldDispatchNow = false
            // A trailing request is already armed; fold this one into it.
            let alreadyPending = pendingReason != nil
            pendingReason = reason
            scheduledGeneration = alreadyPending ? nil : generation
            lock.unlock()
            if alreadyPending {
                AmmoLog.widgetInvalidation.debug(
                    "Coalesced reload request (\(reason.rawValue, privacy: .public))")
                return
            }
        } else {
            shouldDispatchNow = true
            // Retire any delayed closure from an older window before handing
            // this request to WidgetKit immediately.
            generation &+= 1
            pendingReason = nil
            lastDispatchUptime = nowUptime
            scheduledGeneration = nil
            lock.unlock()
        }

        if shouldDispatchNow {
            dispatch(reason: reason, revision: revision)
            return
        }

        guard let scheduledGeneration else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard self.generation == scheduledGeneration else {
                self.lock.unlock()
                return
            }
            let trailing = self.pendingReason
            self.pendingReason = nil
            self.lastDispatchUptime = DispatchTime.now().uptimeNanoseconds
            self.generation &+= 1
            self.lock.unlock()
            guard let trailing else { return }
            self.dispatch(reason: trailing, revision: nil)
        }
        lock.lock()
        let schedulingOverride = schedulingOverride
        lock.unlock()
        if let schedulingOverride {
            schedulingOverride(workItem)
        } else {
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + delay,
                execute: workItem)
        }
    }

    /// Remaining coalescing delay from monotonic uptime. A regressed injected
    /// value is clamped to zero elapsed time, so delay never exceeds the window.
    static func coalescingDelay(
        lastDispatchUptime: UInt64?,
        nowUptime: UInt64
    ) -> TimeInterval {
        guard let lastDispatchUptime else { return 0 }
        let elapsedNanoseconds = nowUptime >= lastDispatchUptime
            ? nowUptime - lastDispatchUptime
            : 0
        let elapsed = TimeInterval(elapsedNanoseconds) / 1_000_000_000
        return max(0, coalescingWindow - elapsed)
    }

    private func dispatch(reason: WidgetInvalidationReason, revision: SharedStoreRevision?) {
        lock.lock()
        let override = dispatchOverride
        lock.unlock()

        let requestedAt = Date()
        AmmoLog.widgetInvalidation.info(
            """
            Requesting widget reload reason=\(reason.rawValue, privacy: .public) \
            at=\(ISO8601DateFormatter().string(from: requestedAt), privacy: .public) \
            \(revision?.logDescription ?? "rev=unknown", privacy: .public)
            """)

        if let override {
            override(reason)
        } else {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Testing

    /// Installs a dispatch override and returns a token that restores the
    /// previous one. Tests use this to observe reload requests.
    func installDispatchOverride(
        _ override: @escaping @Sendable (WidgetInvalidationReason) -> Void,
        schedulingOverride: (@Sendable (DispatchWorkItem) -> Void)? = nil
    ) -> WidgetInvalidatorOverrideToken {
        lock.lock()
        let previous = dispatchOverride
        let previousSchedulingOverride = self.schedulingOverride
        dispatchOverride = override
        self.schedulingOverride = schedulingOverride
        // Coalescing state is per-test; a leftover timestamp would silently
        // swallow the first assertion of the next test.
        generation &+= 1
        lastDispatchUptime = nil
        pendingReason = nil
        lock.unlock()
        return WidgetInvalidatorOverrideToken(
            invalidator: self,
            previous: previous,
            previousSchedulingOverride: previousSchedulingOverride)
    }

    fileprivate func restoreDispatchOverride(
        _ override: (@Sendable (WidgetInvalidationReason) -> Void)?,
        schedulingOverride: (@Sendable (DispatchWorkItem) -> Void)?
    ) {
        lock.lock()
        dispatchOverride = override
        self.schedulingOverride = schedulingOverride
        generation &+= 1
        lastDispatchUptime = nil
        pendingReason = nil
        lock.unlock()
    }
}

/// Restores the previous dispatch override when released.
final class WidgetInvalidatorOverrideToken: @unchecked Sendable {
    private let invalidator: WidgetInvalidator
    private let previous: (@Sendable (WidgetInvalidationReason) -> Void)?
    private let previousSchedulingOverride: (@Sendable (DispatchWorkItem) -> Void)?

    fileprivate init(
        invalidator: WidgetInvalidator,
        previous: (@Sendable (WidgetInvalidationReason) -> Void)?,
        previousSchedulingOverride: (@Sendable (DispatchWorkItem) -> Void)?
    ) {
        self.invalidator = invalidator
        self.previous = previous
        self.previousSchedulingOverride = previousSchedulingOverride
    }

    deinit {
        invalidator.restoreDispatchOverride(
            previous,
            schedulingOverride: previousSchedulingOverride)
    }
}

/// Revision marker published beside the shared usage cache.
///
/// Written by the app under the same lock as the cache itself, immediately
/// after the cache file is committed, so a reader that sees revision N is
/// guaranteed the bytes for N are already on disk.
enum SharedStoreRevisionStore {
    static var fileURL: URL {
        AppGroup.containerURL.appendingPathComponent("usage-states-revision.json")
    }

    static func load() -> SharedStoreRevision? {
        load(from: fileURL)
    }

    static func load(from fileURL: URL) -> SharedStoreRevision? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? UsageCacheCodec.decode(SharedStoreRevision.self, from: data)
    }

    /// Records the revision describing `states`. Never throws: a revision is a
    /// diagnostic, and losing it must not fail the cache write it annotates.
    @discardableResult
    static func record(states: [AccountState], at date: Date = Date()) -> SharedStoreRevision? {
        let snapshots = states.compactMap(\.snapshot)
        let revision = SharedStoreRevision.next(
            after: load(),
            writtenAt: date,
            accountCount: states.count,
            snapshotCount: snapshots.count,
            newestSnapshotAt: snapshots.map(\.fetchedAt).max())
        do {
            let data = try UsageCacheCodec.encode(revision)
            try data.write(to: fileURL, options: .atomic)
            return revision
        } catch {
            AmmoLog.sharedStore.error(
                "Unable to record shared cache revision: \(String(describing: error), privacy: .private)")
            return nil
        }
    }
}
