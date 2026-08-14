import Foundation
import Testing
import UsageKit
@testable import Ammo

@Suite("Usage notification service")
struct UsageNotificationServiceTests {
    @Test("Preference changes schedule from authoritative current snapshots")
    func preferenceChangesUseCurrentSnapshots() async throws {
        let suiteName = "UsageNotificationServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = NotificationPreferencesStorage(suiteName: suiteName)
        var preferences = NotificationPreferences.default
        preferences.masterEnabled = true
        try storage.save(preferences)

        let accountID = try #require(UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        ))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let staleSnapshot = snapshot(
            resetAt: now.addingTimeInterval(2 * 86_400),
            fetchedAt: now.addingTimeInterval(-300)
        )
        try storage.saveEngineState(NotificationEngineState(
            lastSnapshots: [accountID.uuidString.lowercased(): staleSnapshot]
        ))

        let currentReset = now.addingTimeInterval(6 * 86_400)
        let currentSnapshot = snapshot(
            resetAt: currentReset,
            fetchedAt: now.addingTimeInterval(-60)
        )
        let state = AccountState(
            account: StoredAccount(id: accountID, provider: .codex, label: "Codex"),
            snapshot: currentSnapshot
        )
        let center = ServiceRecordingNotificationCenter()
        let service = UsageNotificationService(
            storage: storage,
            center: center,
            currentStates: { [state] }
        )

        await service.preferencesDidChange(now: now)

        let request = try #require(await center.deliveredRequests().last)
        #expect(request.type == .codexWeeklyReset)
        #expect(request.deliverAt == currentReset)
    }

    private func snapshot(resetAt: Date, fetchedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            provider: .codex,
            plan: nil,
            windows: [
                LimitWindow(
                    kind: .weekly,
                    label: "Weekly",
                    usedPercent: 25,
                    resetsAt: resetAt
                )
            ],
            fetchedAt: fetchedAt
        )
    }
}

private actor ServiceRecordingNotificationCenter: LocalNotificationCenter {
    private var delivered: [UsageNotificationRequest] = []

    func isAuthorized() async -> Bool {
        true
    }

    func deliver(_ request: UsageNotificationRequest) async throws {
        delivered.append(request)
    }

    func cancelPending(identifier: String) async {}
    func cancelPending(identifierPrefix: String) async {}
    func cancelPending(accountID: String) async {}

    func deliveredRequests() -> [UsageNotificationRequest] {
        delivered
    }
}
