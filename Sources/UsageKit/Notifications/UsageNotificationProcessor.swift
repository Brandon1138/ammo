import Foundation

/// Stateful notification pass runner. Evaluation and state persistence always
/// run; authorization controls delivery commands only.
public actor UsageNotificationProcessor {
    private let storage: NotificationPreferencesStorage
    private let center: any LocalNotificationCenter
    private let deliveryErrorHandler: @Sendable (String) -> Void
    private var inFlightRequestIdentifiers: Set<String> = []

    public init(
        storage: NotificationPreferencesStorage,
        center: any LocalNotificationCenter,
        deliveryErrorHandler: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.storage = storage
        self.center = center
        self.deliveryErrorHandler = deliveryErrorHandler
    }

    public func process(
        polls: [NotificationPollSnapshot],
        knownAccountIDs: Set<String>,
        now: Date = Date()
    ) async {
        await run(
            polls: polls,
            knownAccountIDs: knownAccountIDs,
            state: storage.loadEngineState(),
            now: now
        )
    }

    /// Re-evaluate the caller's latest persisted snapshots so re-enabled
    /// deterministic notifications are restored without another provider poll.
    public func preferencesDidChange(
        polls: [NotificationPollSnapshot],
        knownAccountIDs: Set<String>,
        now: Date = Date()
    ) async {
        await run(
            polls: polls,
            knownAccountIDs: knownAccountIDs,
            state: storage.loadEngineState(),
            now: now
        )
    }

    private func run(
        polls: [NotificationPollSnapshot],
        knownAccountIDs: Set<String>?,
        state: NotificationEngineState,
        now: Date
    ) async {
        let result = UsageNotificationEngine.evaluate(
            polls: polls,
            knownAccountIDs: knownAccountIDs,
            preferences: storage.load(),
            state: state,
            now: now
        )

        do {
            try storage.saveEngineState(result.state)
        } catch {
            deliveryErrorHandler("Unable to persist notification engine state: \(error)")
        }

        let isAuthorized = await center.isAuthorized()
        for command in result.commands {
            switch command {
            case .deliver(let request) where isAuthorized:
                await deliver(request)
            case .deliver:
                continue
            case .cancelIdentifier(let identifier):
                await center.cancelPending(identifier: identifier)
            case .cancelType(let type):
                await center.cancelPending(identifierPrefix: type.identifierPrefix)
            case .cancelAccount(let accountID):
                await center.cancelPending(accountID: accountID)
            }
        }
    }

    private func deliver(_ request: UsageNotificationRequest) async {
        guard inFlightRequestIdentifiers.insert(request.identifier).inserted else { return }
        defer { inFlightRequestIdentifiers.remove(request.identifier) }

        do {
            try await center.deliver(request)
            markPendingEventDelivered(identifier: request.identifier)
        } catch {
            deliveryErrorHandler("Unable to schedule usage notification: \(error)")
        }
    }

    private func markPendingEventDelivered(identifier: String) {
        var latestState = storage.loadEngineState()
        guard let event = latestState.pendingEvents.removeValue(forKey: identifier) else { return }
        latestState.lastFiredMarkers[event.markerKey] = event.marker
        do {
            try storage.saveEngineState(latestState)
        } catch {
            deliveryErrorHandler("Unable to persist delivered notification marker: \(error)")
        }
    }
}
