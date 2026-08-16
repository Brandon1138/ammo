import Foundation
import Testing
import UserNotifications
import UsageKit
@testable import Ammo

@MainActor
@Suite("Notification settings presentation")
struct NotificationSettingsPresentationTests {
    @Test("A prepared model does not reload preferences during sheet construction")
    func preparedModelUsesStableSnapshot() throws {
        let suiteName = "NotificationSettingsPresentationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = NotificationPreferencesStorage(userDefaults: defaults)
        var persisted = NotificationPreferences.default
        persisted.masterEnabled = false
        persisted.cursorMonthlyReset = false
        try storage.save(persisted)

        var prepared = NotificationPreferences.default
        prepared.masterEnabled = true
        prepared.cursorMonthlyReset = true

        let model = NotificationSettingsModel(
            preparation: NotificationSettingsPreparation(
                preferences: prepared,
                authorizationStatus: .authorized
            ),
            storage: storage
        )

        #expect(model.preferences == prepared)
        #expect(model.preferences != persisted)
        #expect(model.authorizationStatus == .authorized)
    }
}
