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
        masterEnabled = try container.decodeIfPresent(Bool.self, forKey: .masterEnabled) ?? Self.default.masterEnabled
        codexWeeklyReset = try container.decodeIfPresent(Bool.self, forKey: .codexWeeklyReset) ?? Self.default.codexWeeklyReset
        codexSpontaneousReset = try container.decodeIfPresent(Bool.self, forKey: .codexSpontaneousReset) ?? Self.default.codexSpontaneousReset
        codexBankedReset = try container.decodeIfPresent(Bool.self, forKey: .codexBankedReset) ?? Self.default.codexBankedReset
        claudeBankedReset = try container.decodeIfPresent(Bool.self, forKey: .claudeBankedReset) ?? Self.default.claudeBankedReset
        claudeSessionReset = try container.decodeIfPresent(Bool.self, forKey: .claudeSessionReset) ?? Self.default.claudeSessionReset
        claudeWeeklyReset = try container.decodeIfPresent(Bool.self, forKey: .claudeWeeklyReset) ?? Self.default.claudeWeeklyReset
        claudeSpontaneousReset = try container.decodeIfPresent(Bool.self, forKey: .claudeSpontaneousReset) ?? Self.default.claudeSpontaneousReset
        cursorMonthlyReset = try container.decodeIfPresent(Bool.self, forKey: .cursorMonthlyReset) ?? Self.default.cursorMonthlyReset
    }
}
