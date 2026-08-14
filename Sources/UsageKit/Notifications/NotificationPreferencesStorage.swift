import Foundation

/// JSON persistence shared by app UI and notification delivery code.
public struct NotificationPreferencesStorage {
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func load() -> NotificationPreferences {
        guard let data = userDefaults.data(forKey: NotificationPreferences.storageKey),
              let preferences = try? JSONDecoder().decode(NotificationPreferences.self, from: data) else {
            return .default
        }
        return preferences
    }

    public func save(_ preferences: NotificationPreferences) throws {
        let data = try JSONEncoder().encode(preferences)
        userDefaults.set(data, forKey: NotificationPreferences.storageKey)
    }
}
