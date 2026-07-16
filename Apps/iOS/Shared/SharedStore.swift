import Foundation
import UsageKit

/// Everything in Shared/ is compiled into both the app and the widget extension.
/// The app is the only writer; the widget only reads.

enum AppGroup {
    static let id = "group.com.brandon.ammo"

    static var containerURL: URL {
        // Falls back to tmp so previews / a missing entitlement degrade to
        // "no data" instead of crashing.
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.temporaryDirectory
    }
}

/// One configured account. Tokens live in the Keychain, never in this struct.
struct StoredAccount: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var provider: ProviderID
    var label: String
    /// Tokens were pasted from a desktop CLI rather than issued to this device.
    /// Refreshing could rotate the CLI's refresh token and log it out, so
    /// refresh is forbidden for imported accounts.
    var tokensImported: Bool

    init(id: UUID = UUID(), provider: ProviderID, label: String, tokensImported: Bool = false) {
        self.id = id
        self.provider = provider
        self.label = label
        self.tokensImported = tokensImported
    }
}

/// An account plus its latest fetch outcome — the unit the widget renders.
struct AccountState: Codable, Identifiable, Sendable {
    var account: StoredAccount
    var snapshot: UsageSnapshot?
    var lastError: String?
    var updatedAt: Date?

    var id: UUID { account.id }
}

enum SharedStore {
    static var fileURL: URL {
        AppGroup.containerURL.appendingPathComponent("usage-states.json")
    }

    static func load() -> [AccountState] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AccountState].self, from: data)) ?? []
    }

    static func save(_ states: [AccountState]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(states) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension UsageSnapshot {
    /// The most-consumed window — what single-gauge surfaces display.
    var worstWindow: LimitWindow? {
        windows.max { $0.usedPercent < $1.usedPercent }
    }
}
