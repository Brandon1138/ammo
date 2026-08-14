import Foundation

/// JSON persistence shared by app UI and notification delivery code.
public struct NotificationPreferencesStorage: @unchecked Sendable {
    public static let engineStateStorageKey = "ammo.notificationEngineState"

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Centralizes App Group lookup and its fallback so every notification
    /// consumer resolves the same UserDefaults container.
    public init(suiteName: String) {
        self.init(userDefaults: UserDefaults(suiteName: suiteName) ?? .standard)
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

    public func loadEngineState() -> NotificationEngineState {
        guard let data = userDefaults.data(forKey: Self.engineStateStorageKey),
              let state = try? JSONDecoder().decode(NotificationEngineState.self, from: data) else {
            return NotificationEngineState()
        }
        return state
    }

    public func saveEngineState(_ state: NotificationEngineState) throws {
        let data = try JSONEncoder().encode(state)
        userDefaults.set(data, forKey: Self.engineStateStorageKey)
    }
}
