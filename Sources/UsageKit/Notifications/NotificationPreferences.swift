import Foundation

/// Persisted notification preferences shared between the Settings UI and the notification engine.
/// Stored JSON-encoded in UserDefaults under `storageKey`.
public struct NotificationPreferences: Codable, Equatable, Sendable {
    public var masterEnabled: Bool
    public var codexWeeklyReset: Bool
    public var codexSpontaneousReset: Bool
    public var codexBankedReset: Bool
    public var claudeSessionReset: Bool
    public var claudeWeeklyReset: Bool
    public var claudeSpontaneousReset: Bool
    public var cursorMonthlyReset: Bool

    public static let storageKey = "ammo.notificationPreferences"

    public static let `default` = NotificationPreferences(
        masterEnabled: false,
        codexWeeklyReset: true,
        codexSpontaneousReset: true,
        codexBankedReset: true,
        claudeSessionReset: true,
        claudeWeeklyReset: true,
        claudeSpontaneousReset: true,
        cursorMonthlyReset: true
    )
}
