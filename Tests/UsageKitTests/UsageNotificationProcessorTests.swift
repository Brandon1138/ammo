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

        await processor.preferencesDidChange(now: now)

        #expect(Set(await center.cancelledPrefixes()) == Set(
            UsageNotificationType.allCases.map(\.identifierPrefix)
        ))
    }

    private func snapshot(
        usedPercent: Double,
        resetAt: Date,
        fetchedAt: Date
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex,
            plan: nil,
            windows: [LimitWindow(
                kind: .weekly,
                label: "Weekly",
                usedPercent: usedPercent,
                resetsAt: resetAt
            )],
            fetchedAt: fetchedAt
        )
    }
}

private actor RecordingNotificationCenter: LocalNotificationCenter {
    private let authorization: Bool
    private var delivered: [UsageNotificationRequest] = []
    private var cancelledIdentifiersStorage: [String] = []
    private var cancelledPrefixesStorage: [String] = []
    private var cancelledAccountsStorage: [String] = []

    init(isAuthorized: Bool) {
        authorization = isAuthorized
    }

    func isAuthorized() async -> Bool {
        authorization
    }

    func deliver(_ request: UsageNotificationRequest) async throws {
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

    func cancelledPrefixes() -> [String] {
        cancelledPrefixesStorage
    }
}
