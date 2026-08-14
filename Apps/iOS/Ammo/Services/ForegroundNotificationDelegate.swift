import UserNotifications

final class ForegroundNotificationDelegate: NSObject,
    UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    static let shared = ForegroundNotificationDelegate()

    func install(center: UNUserNotificationCenter = .current()) {
        center.delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
