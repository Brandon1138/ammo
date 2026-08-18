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

    private let lock = NSLock()
    private var lastDispatchAt: Date?
    private var pendingReason: WidgetInvalidationReason?

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
        now: Date = Date()
    ) {
        guard !Self.isWidgetProcess else {
            AmmoLog.widgetInvalidation.debug(
                "Skipping reload request from the widget process (\(reason.rawValue, privacy: .public))")
            return
        }

        let shouldDispatchNow: Bool
        let delay: TimeInterval
        lock.lock()
        if let lastDispatchAt, now.timeIntervalSince(lastDispatchAt) < Self.coalescingWindow {
            shouldDispatchNow = false
            delay = Self.coalescingWindow - now.timeIntervalSince(lastDispatchAt)
            // A trailing request is already armed; fold this one into it.
            let alreadyPending = pendingReason != nil
            pendingReason = reason
            lock.unlock()
            if alreadyPending {
                AmmoLog.widgetInvalidation.debug(
                    "Coalesced reload request (\(reason.rawValue, privacy: .public))")
                return
            }
        } else {
            shouldDispatchNow = true
            delay = 0
            lastDispatchAt = now
            lock.unlock()
        }

        if shouldDispatchNow {
            dispatch(reason: reason, revision: revision)
            return
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let trailing = self.pendingReason
            self.pendingReason = nil
            self.lastDispatchAt = Date()
            self.lock.unlock()
            guard let trailing else { return }
            self.dispatch(reason: trailing, revision: nil)
        }
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
        _ override: @escaping @Sendable (WidgetInvalidationReason) -> Void
    ) -> WidgetInvalidatorOverrideToken {
        lock.lock()
        let previous = dispatchOverride
        dispatchOverride = override
        // Coalescing state is per-test; a leftover timestamp would silently
        // swallow the first assertion of the next test.
        lastDispatchAt = nil
        pendingReason = nil
        lock.unlock()
        return WidgetInvalidatorOverrideToken(invalidator: self, previous: previous)
    }

    fileprivate func restoreDispatchOverride(
        _ override: (@Sendable (WidgetInvalidationReason) -> Void)?
    ) {
        lock.lock()
        dispatchOverride = override
        lastDispatchAt = nil
        pendingReason = nil
        lock.unlock()
    }
}

/// Restores the previous dispatch override when released.
final class WidgetInvalidatorOverrideToken: @unchecked Sendable {
    private let invalidator: WidgetInvalidator
    private let previous: (@Sendable (WidgetInvalidationReason) -> Void)?

    fileprivate init(
        invalidator: WidgetInvalidator,
        previous: (@Sendable (WidgetInvalidationReason) -> Void)?
    ) {
        self.invalidator = invalidator
        self.previous = previous
    }

    deinit {
        invalidator.restoreDispatchOverride(previous)
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
