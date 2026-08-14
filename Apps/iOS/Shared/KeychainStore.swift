import Foundation
import Security
import UsageKit

/// Token storage shared by the containing app and widget extension. Items use
/// the existing App Group as their Keychain access group, remain local to this
/// device, and are available after the first unlock for background refreshes.
enum KeychainStore {
    static let service = "com.brandon.ammo.tokens"
    private static let accessGroupInfoKey = "AmmoKeychainAccessGroup"

    struct KeychainError: Error, CustomStringConvertible {
        let status: OSStatus
        var description: String { "Keychain error \(status)" }
    }

    static func save(_ tokens: OAuthTokens, for id: UUID) throws {
        try AccountDeletionStore.requireActive(id, timeout: 5)
        let data = try JSONEncoder().encode(tokens)
        let accessGroup = try configuredAccessGroup()
        let query = baseQuery(for: id, accessGroup: accessGroup)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            let addStatus = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError(status: updateStatus)
        }
        switch AccountDeletionStore.status(for: id, timeout: 5) {
        case .active:
            return
        case .deleted:
            delete(for: id)
            throw CancellationError()
        case .unknown:
            // Rotation may already have invalidated the prior refresh token.
            // Keep the newly written valid pair; retry tombstone validation
            // later instead of turning a transient file-lock failure into loss.
            throw AccountDeletionStore.StatusUnavailableError()
        }
    }

    static func load(for id: UUID) -> OAuthTokens? {
        guard let accessGroup = try? configuredAccessGroup() else {
            AmmoLog.refresh.fault("Shared Keychain access group is unavailable")
            return nil
        }
        return loadItem(for: id, accessGroup: accessGroup)?.tokens
    }

    /// Existing installs stored credentials in the app target's private default
    /// group. The app calls this once per account after an update so the widget
    /// can read them without asking the user to authenticate again.
    static func migrateLegacyItemIfNeeded(for id: UUID) throws {
        let accessGroup = try configuredAccessGroup()
        guard load(for: id) == nil,
              let legacy = loadItem(for: id, accessGroup: nil)
        else { return }

        try save(legacy.tokens, for: id)
        if let legacyAccessGroup = legacy.accessGroup,
           legacyAccessGroup != accessGroup {
            SecItemDelete(baseQuery(for: id, accessGroup: legacyAccessGroup) as CFDictionary)
        }
    }

    static func delete(for id: UUID) {
        if let accessGroup = try? configuredAccessGroup() {
            SecItemDelete(baseQuery(for: id, accessGroup: accessGroup) as CFDictionary)
        }
        // The nil query targets the pre-migration item in the app's default
        // Keychain group. Keep both deletes so account removal works before and
        // after migration without touching unrelated Keychain items.
        SecItemDelete(baseQuery(for: id, accessGroup: nil) as CFDictionary)
    }

    static func deleteOrThrow(for id: UUID) throws {
        let accessGroup = try configuredAccessGroup()
        try deleteItem(for: id, accessGroup: accessGroup)
        try deleteItem(for: id, accessGroup: nil)
    }

    private struct ConfigurationError: Error {}

    private static func configuredAccessGroup() throws -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: accessGroupInfoKey) as? String,
              !value.isEmpty,
              !value.contains("$(") else {
            throw ConfigurationError()
        }
        return value
    }

    private struct LoadedItem {
        let tokens: OAuthTokens
        let accessGroup: String?
    }

    private static func loadItem(for id: UUID, accessGroup: String?) -> LoadedItem? {
        var query = baseQuery(for: id, accessGroup: accessGroup)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let item = result as? [String: Any],
              let data = item[kSecValueData as String] as? Data,
              let tokens = try? JSONDecoder().decode(OAuthTokens.self, from: data)
        else { return nil }

        return LoadedItem(tokens: tokens,
                          accessGroup: item[kSecAttrAccessGroup as String] as? String)
    }

    private static func baseQuery(for id: UUID, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private static func deleteItem(for id: UUID, accessGroup: String?) throws {
        let status = SecItemDelete(baseQuery(for: id, accessGroup: accessGroup) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}
