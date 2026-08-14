import Foundation
import Testing
@testable import UsageKit

@Suite("Notification preferences storage")
struct NotificationPreferencesStorageTests {
    @Test("Preferences round-trip as JSON in UserDefaults")
    func roundTrip() throws {
        let suiteName = "NotificationPreferencesStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = NotificationPreferencesStorage(userDefaults: defaults)
        var expected = NotificationPreferences.default
        expected.masterEnabled = true
        expected.codexBankedReset = false
        expected.claudeSessionReset = false
        expected.cursorMonthlyReset = false

        try storage.save(expected)

        #expect(defaults.data(forKey: NotificationPreferences.storageKey) != nil)
        #expect(storage.load() == expected)
    }

    @Test("Settings writer and service reader share suite and engine state")
    func separateCallPathsRoundTripThroughOneSuite() throws {
        let suiteName = "NotificationPreferencesStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settingsStorage = NotificationPreferencesStorage(suiteName: suiteName)
        let serviceStorage = NotificationPreferencesStorage(suiteName: suiteName)
        var preferences = NotificationPreferences.default
        preferences.masterEnabled = true
        preferences.claudeSessionReset = false
        let state = NotificationEngineState(lastFiredMarkers: ["marker": "value"])

        try settingsStorage.save(preferences)
        try serviceStorage.saveEngineState(state)

        #expect(serviceStorage.load() == preferences)
        #expect(settingsStorage.loadEngineState() == state)
    }

    @Test("Missing and invalid data use defaults")
    func fallback() throws {
        let suiteName = "NotificationPreferencesStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storage = NotificationPreferencesStorage(userDefaults: defaults)
        #expect(storage.load() == .default)

        defaults.set(Data("not json".utf8), forKey: NotificationPreferences.storageKey)
        #expect(storage.load() == .default)
    }
}
