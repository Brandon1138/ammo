import Foundation

/// Persisted notification preferences shared between the Settings UI and the notification engine.
/// Stored JSON-encoded in UserDefaults under `storageKey`.
public struct NotificationPreferences: Codable, Equatable, Sendable {
    public var masterEnabled: Bool
    public var codexWeeklyReset: Bool
    public var codexSpontaneousReset: Bool
    public var codexBankedReset: Bool
    public var claudeBankedReset: Bool
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
        claudeBankedReset: true,
        claudeSessionReset: true,
        claudeWeeklyReset: true,
        claudeSpontaneousReset: true,
        cursorMonthlyReset: true
    )
}

extension NotificationPreferences {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = .default
        masterEnabled = try container.decode(Bool.self, forKey: .masterEnabled)
        codexWeeklyReset = try container.decode(Bool.self, forKey: .codexWeeklyReset)
        codexSpontaneousReset = try container.decode(Bool.self, forKey: .codexSpontaneousReset)
        codexBankedReset = try container.decode(Bool.self, forKey: .codexBankedReset)
        claudeBankedReset = try container.decodeIfPresent(Bool.self, forKey: .claudeBankedReset) ?? true
        claudeSessionReset = try container.decode(Bool.self, forKey: .claudeSessionReset)
        claudeWeeklyReset = try container.decode(Bool.self, forKey: .claudeWeeklyReset)
        claudeSpontaneousReset = try container.decode(Bool.self, forKey: .claudeSpontaneousReset)
        cursorMonthlyReset = try container.decode(Bool.self, forKey: .cursorMonthlyReset)
    }
}
