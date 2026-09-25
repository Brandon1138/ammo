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
        expected.claudeBankedReset = false
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

    @Test("Existing preferences retain values when Claude banked toggle is absent")
    func legacyPreferencesDecode() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "masterEnabled": true,
            "codexWeeklyReset": false,
            "codexSpontaneousReset": true,
            "codexBankedReset": false,
            "claudeSessionReset": true,
            "claudeWeeklyReset": true,
            "claudeSpontaneousReset": false,
            "cursorMonthlyReset": true,
        ])
        let preferences = try JSONDecoder().decode(NotificationPreferences.self, from: data)
        #expect(preferences.masterEnabled)
        #expect(!preferences.codexBankedReset)
        #expect(!preferences.claudeSpontaneousReset)
        #expect(preferences.claudeBankedReset)
    }

    @Test("One missing preference leaves other saved values intact")
    func oneMissingPreferenceDefaultsIndividually() throws {
        let saved: [String: Bool] = [
            "masterEnabled": true,
            "codexWeeklyReset": false,
            "codexSpontaneousReset": false,
            "codexBankedReset": false,
            "claudeBankedReset": false,
            "claudeSessionReset": false,
            "claudeWeeklyReset": false,
            "claudeSpontaneousReset": false,
            "cursorMonthlyReset": false,
        ]
        for missing in saved.keys {
            var partial = saved
            partial.removeValue(forKey: missing)
            let data = try JSONSerialization.data(withJSONObject: partial)
            let preferences = try JSONDecoder().decode(NotificationPreferences.self, from: data)
            #expect(preferences.masterEnabled == (missing == "masterEnabled" ? false : true))
            #expect(preferences.codexWeeklyReset == (missing == "codexWeeklyReset"))
            #expect(preferences.codexSpontaneousReset == (missing == "codexSpontaneousReset"))
            #expect(preferences.codexBankedReset == (missing == "codexBankedReset"))
            #expect(preferences.claudeBankedReset == (missing == "claudeBankedReset"))
            #expect(preferences.claudeSessionReset == (missing == "claudeSessionReset"))
            #expect(preferences.claudeWeeklyReset == (missing == "claudeWeeklyReset"))
            #expect(preferences.claudeSpontaneousReset == (missing == "claudeSpontaneousReset"))
            #expect(preferences.cursorMonthlyReset == (missing == "cursorMonthlyReset"))
        }
    }

    @Test("Engine state created before pending events remains readable")
    func legacyEngineStateDecoding() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "lastSnapshots": [:],
            "claudeSessionObservations": [:],
            "lastFiredMarkers": ["marker": "value"],
        ])

        let state = try JSONDecoder().decode(NotificationEngineState.self, from: data)

        #expect(state.lastFiredMarkers == ["marker": "value"])
        #expect(state.pendingEvents.isEmpty)
    }
}
