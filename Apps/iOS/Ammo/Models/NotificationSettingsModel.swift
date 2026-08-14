import Foundation
import Observation
import UserNotifications
import UsageKit

@MainActor
@Observable
final class NotificationSettingsModel {
    private let center: UNUserNotificationCenter
    private let storage: NotificationPreferencesStorage

    private(set) var preferences: NotificationPreferences
    private(set) var authorizationStatus: UNAuthorizationStatus?
    private(set) var isUpdatingAuthorization = false
    private(set) var authorizationRequestFailed = false

    init(
        center: UNUserNotificationCenter = .current(),
        userDefaults: UserDefaults = UserDefaults(suiteName: AppGroup.id) ?? .standard
    ) {
        self.center = center
        storage = NotificationPreferencesStorage(userDefaults: userDefaults)
        preferences = storage.load()
    }

    var permissionDenied: Bool {
        authorizationStatus == .denied
    }

    func refreshAuthorizationStatus() async {
        let status = await center.notificationSettings().authorizationStatus
        authorizationStatus = status
        authorizationRequestFailed = false

        if status == .denied, preferences.masterEnabled {
            preferences.masterEnabled = false
            persist()
        }
    }

    func setMasterEnabled(_ enabled: Bool) async {
        guard enabled else {
            preferences.masterEnabled = false
            authorizationRequestFailed = false
            persist()
            return
        }

        isUpdatingAuthorization = true
        defer { isUpdatingAuthorization = false }

        var status = await center.notificationSettings().authorizationStatus
        authorizationStatus = status
        authorizationRequestFailed = false

        if status == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                authorizationRequestFailed = true
            }
            status = await center.notificationSettings().authorizationStatus
            authorizationStatus = status
        }

        switch status {
        case .authorized, .provisional, .ephemeral:
            preferences.masterEnabled = true
        case .denied, .notDetermined:
            preferences.masterEnabled = false
        @unknown default:
            preferences.masterEnabled = false
        }
        persist()
    }

    func set(_ keyPath: WritableKeyPath<NotificationPreferences, Bool>, to enabled: Bool) {
        preferences[keyPath: keyPath] = enabled
        persist()
    }

    private func persist() {
        do {
            try storage.save(preferences)
        } catch {
            assertionFailure("Unable to persist notification preferences: \(error)")
        }
    }
}
