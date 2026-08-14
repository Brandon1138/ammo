import Foundation
import Testing
@testable import UsageKit

@Suite("Notification processor")
struct UsageNotificationProcessorTests {
    private let accountID = "11111111-1111-1111-1111-111111111111"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Denied authorization still advances and persists engine state")
    func deniedAuthorizationAdvancesState() async throws {
        let suiteName = "UsageNotificationProcessorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = NotificationPreferencesStorage(suiteName: suiteName)
        var preferences = NotificationPreferences.default
        preferences.masterEnabled = true
        try storage.save(preferences)

        let previous = snapshot(
            usedPercent: 50,
            resetAt: now.addingTimeInterval(6 * 86_400),
            fetchedAt: now.addingTimeInterval(-300)
        )
        try storage.saveEngineState(NotificationEngineState(
            lastSnapshots: [accountID: previous]
        ))

        let current = snapshot(
            usedPercent: 0,
            resetAt: now.addingTimeInterval(7 * 86_400),
            fetchedAt: now
        )
        let center = RecordingNotificationCenter(isAuthorized: false)
        let processor = UsageNotificationProcessor(storage: storage, center: center)

        await processor.process(
            polls: [NotificationPollSnapshot(accountID: accountID, snapshot: current)],
            knownAccountIDs: [accountID],
            now: now
        )

        #expect(storage.loadEngineState().lastSnapshots[accountID] == current)
        #expect(await center.deliveredRequests().isEmpty)
    }

    @Test("Denied authorization does not block settings cancellation pass")
    func deniedAuthorizationStillCancelsDisabledTypes() async throws {
        let suiteName = "UsageNotificationProcessorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = NotificationPreferencesStorage(suiteName: suiteName)
        try storage.save(.default)
        let center = RecordingNotificationCenter(isAuthorized: false)
        let processor = UsageNotificationProcessor(storage: storage, center: center)

        await processor.preferencesDidChange(
            polls: [],
            knownAccountIDs: [],
            now: now
        )

        #expect(Set(await center.cancelledPrefixes()) == Set(
            UsageNotificationType.allCases.map(\.identifierPrefix)
        ))
    }

    @Test("Re-enabling a deterministic type restores its latest schedule without another poll")
    func reenableRestoresLatestDeterministicScheduleWithoutPoll() async throws {
        let suiteName = "UsageNotificationProcessorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = NotificationPreferencesStorage(suiteName: suiteName)
        var preferences = NotificationPreferences.default
        preferences.masterEnabled = true
        preferences.codexWeeklyReset = false
        try storage.save(preferences)

        let stale = snapshot(
            usedPercent: 20,
            resetAt: now.addingTimeInterval(5 * 86_400),
            fetchedAt: now.addingTimeInterval(-300)
        )
        try storage.saveEngineState(NotificationEngineState(
            lastSnapshots: [accountID: stale]
        ))
        let latestReset = now.addingTimeInterval(6 * 86_400)
        let latest = snapshot(
            usedPercent: 25,
            resetAt: latestReset,
            fetchedAt: now.addingTimeInterval(-60)
        )

        let center = RecordingNotificationCenter(isAuthorized: true)
        let processor = UsageNotificationProcessor(storage: storage, center: center)

        await processor.preferencesDidChange(
            polls: [NotificationPollSnapshot(accountID: accountID, snapshot: latest)],
            knownAccountIDs: [accountID],
            now: now
        )

        #expect(await center.deliveredRequests().isEmpty)
        #expect(await center.cancelledPrefixes().contains(
            UsageNotificationType.codexWeeklyReset.identifierPrefix
        ))

        preferences.codexWeeklyReset = true
        try storage.save(preferences)
        await processor.preferencesDidChange(
            polls: [NotificationPollSnapshot(accountID: accountID, snapshot: latest)],
            knownAccountIDs: [accountID],
            now: now
        )

        let restored = try #require(await center.deliveredRequests().last)
        #expect(restored.type == .codexWeeklyReset)
        #expect(restored.deliverAt == latestReset)
    }

    @Test("Enabling master switch schedules every applicable current snapshot")
    func masterEnableSchedulesCurrentSnapshotsWithEmptyEngineState() async throws {
        let suiteName = "UsageNotificationProcessorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = NotificationPreferencesStorage(suiteName: suiteName)
        try storage.save(.default)
        try storage.saveEngineState(NotificationEngineState())

        let codexID = "11111111-1111-1111-1111-111111111111"
        let claudeID = "22222222-2222-2222-2222-222222222222"
        let cursorID = "33333333-3333-3333-3333-333333333333"
        let claudeSessionReset = now.addingTimeInterval(5 * 3_600)
        let polls = [
            NotificationPollSnapshot(
                accountID: codexID,
                snapshot: snapshot(
                    provider: .codex,
                    usedPercent: 20,
                    resetAt: now.addingTimeInterval(6 * 86_400),
                    fetchedAt: now.addingTimeInterval(-60)
                )
            ),
            NotificationPollSnapshot(
                accountID: claudeID,
                snapshot: snapshot(
                    provider: .claude,
                    usedPercent: 30,
                    resetAt: now.addingTimeInterval(5 * 86_400),
                    fetchedAt: now.addingTimeInterval(-60),
                    sessionUsedPercent: 10,
                    sessionResetAt: claudeSessionReset
                )
            ),
            NotificationPollSnapshot(
                accountID: cursorID,
                snapshot: snapshot(
                    provider: .cursor,
                    usedPercent: 40,
                    resetAt: now.addingTimeInterval(20 * 86_400),
                    fetchedAt: now.addingTimeInterval(-60)
                )
            )
        ]

        let center = RecordingNotificationCenter(isAuthorized: true)
        let processor = UsageNotificationProcessor(storage: storage, center: center)

        await processor.preferencesDidChange(
            polls: polls,
            knownAccountIDs: [codexID, claudeID, cursorID],
            now: now
        )
        #expect(await center.deliveredRequests().isEmpty)

        var preferences = NotificationPreferences.default
        preferences.masterEnabled = true
        try storage.save(preferences)
        await processor.preferencesDidChange(
            polls: polls,
            knownAccountIDs: [codexID, claudeID, cursorID],
            now: now
        )

        #expect(Set(await center.deliveredRequests().map(\.type)) == [
            .codexWeeklyReset,
            .claudeSessionReset,
            .claudeWeeklyReset,
            .cursorMonthlyReset
        ])
    }

    @Test("Transient delivery failures retain spontaneous and banked events for retry")
    func transientDeliveryFailuresRemainRetryable() async throws {
        let suiteName = "UsageNotificationProcessorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = NotificationPreferencesStorage(suiteName: suiteName)
        var preferences = NotificationPreferences.default
        preferences.masterEnabled = true
        preferences.codexWeeklyReset = false
        try storage.save(preferences)

        let previous = snapshot(
            usedPercent: 50,
            resetAt: now.addingTimeInterval(6 * 86_400),
            fetchedAt: now.addingTimeInterval(-300),
            banked: 0
        )
        try storage.saveEngineState(NotificationEngineState(
            lastSnapshots: [accountID: previous]
        ))
        let current = snapshot(
            usedPercent: 0,
            resetAt: now.addingTimeInterval(7 * 86_400),
            fetchedAt: now,
            banked: 1
        )
        let center = RecordingNotificationCenter(
            isAuthorized: true,
            deliveryFailures: 2
        )
        let processor = UsageNotificationProcessor(storage: storage, center: center)

        await processor.process(
            polls: [NotificationPollSnapshot(accountID: accountID, snapshot: current)],
            knownAccountIDs: [accountID],
            now: now
        )

        let failedState = storage.loadEngineState()
        #expect(failedState.pendingEvents.count == 2)
        #expect(failedState.lastFiredMarkers.isEmpty)
        #expect(await center.deliveryAttemptCount() == 2)

        let retryProcessor = UsageNotificationProcessor(storage: storage, center: center)
        await retryProcessor.process(polls: [], knownAccountIDs: [accountID], now: now)

        let deliveredState = storage.loadEngineState()
        #expect(deliveredState.pendingEvents.isEmpty)
        #expect(deliveredState.lastFiredMarkers.count == 2)
        #expect(Set(await center.deliveredRequests().map(\.type)) == [
            .codexSpontaneousReset,
            .codexBankedReset
        ])
        #expect(await center.deliveryAttemptCount() == 4)

        let postSuccessProcessor = UsageNotificationProcessor(storage: storage, center: center)
        await postSuccessProcessor.process(polls: [], knownAccountIDs: [accountID], now: now)
        #expect(await center.deliveryAttemptCount() == 4)
    }

    private func snapshot(
        provider: ProviderID = .codex,
        usedPercent: Double,
        resetAt: Date,
        fetchedAt: Date,
        sessionUsedPercent: Double? = nil,
        sessionResetAt: Date? = nil,
        banked: Int? = nil
    ) -> UsageSnapshot {
        var windows = [LimitWindow(
            kind: provider == .cursor ? .monthly : .weekly,
            label: provider == .cursor ? "Monthly" : "Weekly",
            usedPercent: usedPercent,
            resetsAt: resetAt
        )]
        if let sessionUsedPercent {
            windows.insert(LimitWindow(
                kind: .session,
                label: "Session",
                usedPercent: sessionUsedPercent,
                resetsAt: sessionResetAt
            ), at: 0)
        }
        return UsageSnapshot(
            provider: provider,
            plan: nil,
            windows: windows,
            resetCreditsAvailable: banked,
            fetchedAt: fetchedAt
        )
    }
}

private actor RecordingNotificationCenter: LocalNotificationCenter {
    private let authorization: Bool
    private var deliveryFailuresRemaining: Int
    private var deliveryAttempts: [UsageNotificationRequest] = []
    private var delivered: [UsageNotificationRequest] = []
    private var cancelledIdentifiersStorage: [String] = []
    private var cancelledPrefixesStorage: [String] = []
    private var cancelledAccountsStorage: [String] = []

    init(isAuthorized: Bool, deliveryFailures: Int = 0) {
        authorization = isAuthorized
        deliveryFailuresRemaining = deliveryFailures
    }

    func isAuthorized() async -> Bool {
        authorization
    }

    func deliver(_ request: UsageNotificationRequest) async throws {
        deliveryAttempts.append(request)
        if deliveryFailuresRemaining > 0 {
            deliveryFailuresRemaining -= 1
            throw RecordingNotificationCenterError.transientDeliveryFailure
        }
        delivered.append(request)
    }

    func cancelPending(identifier: String) async {
        cancelledIdentifiersStorage.append(identifier)
    }

    func cancelPending(identifierPrefix: String) async {
        cancelledPrefixesStorage.append(identifierPrefix)
    }

    func cancelPending(accountID: String) async {
        cancelledAccountsStorage.append(accountID)
    }

    func deliveredRequests() -> [UsageNotificationRequest] {
        delivered
    }

    func deliveryAttemptCount() -> Int {
        deliveryAttempts.count
    }

    func cancelledPrefixes() -> [String] {
        cancelledPrefixesStorage
    }
}

private enum RecordingNotificationCenterError: Error {
    case transientDeliveryFailure
}
