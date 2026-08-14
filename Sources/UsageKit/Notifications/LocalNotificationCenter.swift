import Foundation

/// Narrow delivery seam. Production wraps UNUserNotificationCenter; pure
/// notification-engine tests never import or call UserNotifications.
public protocol LocalNotificationCenter: Sendable {
    func isAuthorized() async -> Bool
    func deliver(_ request: UsageNotificationRequest) async throws
    func cancelPending(identifier: String) async
    func cancelPending(identifierPrefix: String) async
}
