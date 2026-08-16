import Foundation
import Observation
import UserNotifications
import UsageKit

struct NotificationSettingsPreparation: Sendable {
    let preferences: NotificationPreferences
    let authorizationStatus: UNAuthorizationStatus
}

@MainActor
@Observable
final class NotificationSettingsModel {
    private let center: UNUserNotificationCenter
    private let storage: NotificationPreferencesStorage
    private let notificationService: UsageNotificationService

    private(set) var preferences: NotificationPreferences
    private(set) var authorizationStatus: UNAuthorizationStatus?
    private(set) var isUpdatingAuthorization = false
    private(set) var authorizationRequestFailed = false

    init(
        center: UNUserNotificationCenter = .current(),
        storage: NotificationPreferencesStorage = NotificationPreferencesStorage(
            suiteName: AppGroup.id
        ),
        notificationService: UsageNotificationService = .shared
    ) {
        self.center = center
        self.storage = storage
        self.notificationService = notificationService
        preferences = storage.load()
    }

    init(
        preparation: NotificationSettingsPreparation,
        center: UNUserNotificationCenter = .current(),
        storage: NotificationPreferencesStorage = NotificationPreferencesStorage(
            suiteName: AppGroup.id
        ),
        notificationService: UsageNotificationService = .shared
    ) {
        self.center = center
        self.storage = storage
        self.notificationService = notificationService
        preferences = preparation.preferences
        authorizationStatus = preparation.authorizationStatus
    }

    nonisolated static func prepareForPresentation() async -> NotificationSettingsPreparation {
        await Task.detached(priority: .userInitiated) {
            let storage = NotificationPreferencesStorage(suiteName: AppGroup.id)
            let preferences = storage.load()
            let authorizationStatus = await UNUserNotificationCenter.current()
                .notificationSettings().authorizationStatus

            return NotificationSettingsPreparation(
                preferences: preferences,
                authorizationStatus: authorizationStatus
            )
        }.value
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
            Task { await notificationService.preferencesDidChange() }
        } catch {
            assertionFailure("Unable to persist notification preferences: \(error)")
        }
    }
}
