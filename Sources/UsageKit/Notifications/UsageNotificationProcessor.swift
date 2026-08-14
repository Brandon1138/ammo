import Foundation

/// Stateful notification pass runner. Evaluation and state persistence always
/// run; authorization controls delivery commands only.
public actor UsageNotificationProcessor {
    private let storage: NotificationPreferencesStorage
    private let center: any LocalNotificationCenter
    private let deliveryErrorHandler: @Sendable (String) -> Void

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
        await run(polls: polls, knownAccountIDs: knownAccountIDs, now: now)
    }

    /// Settings changes need an immediate cancel-only pass without treating
    /// absent polls as account removals.
    public func preferencesDidChange(now: Date = Date()) async {
        await run(polls: [], knownAccountIDs: nil, now: now)
    }

    private func run(
        polls: [NotificationPollSnapshot],
        knownAccountIDs: Set<String>?,
        now: Date
    ) async {
        let result = UsageNotificationEngine.evaluate(
            polls: polls,
            knownAccountIDs: knownAccountIDs,
            preferences: storage.load(),
            state: storage.loadEngineState(),
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
                do {
                    try await center.deliver(request)
                } catch {
                    deliveryErrorHandler("Unable to schedule usage notification: \(error)")
                }
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
}
