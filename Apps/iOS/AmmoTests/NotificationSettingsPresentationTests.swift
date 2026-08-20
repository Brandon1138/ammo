import Foundation
import Testing
import UserNotifications
import UsageKit
@testable import Ammo

@MainActor
@Suite("Notification settings presentation")
struct NotificationSettingsPresentationTests {
    @Test("Constructing the model loads persisted preferences synchronously")
    func modelLoadsPreferencesWithoutAwaiting() throws {
        let suiteName = "NotificationSettingsPresentationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = NotificationPreferencesStorage(userDefaults: defaults)
        var persisted = NotificationPreferences.default
        persisted.masterEnabled = true
        persisted.cursorMonthlyReset = false
        try storage.save(persisted)

        let model = NotificationSettingsModel(storage: storage)

        #expect(model.preferences == persisted)
    }

    @Test("Authorization status stays unresolved until it is refreshed")
    func authorizationStatusIsResolvedOutOfBand() throws {
        let suiteName = "NotificationSettingsPresentationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = NotificationPreferencesStorage(userDefaults: defaults)
        let model = NotificationSettingsModel(storage: storage)

        // Sheet presentation must never wait on the notification center, so the
        // status is nil at construction and only the master toggle is gated.
        #expect(model.authorizationStatus == nil)
        #expect(model.permissionDenied == false)
    }
}
