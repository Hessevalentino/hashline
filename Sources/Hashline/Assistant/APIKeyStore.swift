import Foundation
import HashlineCore
import Security

/// The assistant's API keys, one per provider, only in the Keychain (ADR 0019): this device only,
/// readable while unlocked, never synchronized, never in UserDefaults, logs or exports.
enum APIKeyStore {
    private static let service = "cz.hashline.Hashline.assistant"

    static func key(for provider: AssistantProvider) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            return nil
        }
        return key
    }

    /// Reads only the item's attributes, not the key: the key's decryption is what asks for Keychain
    /// access after a new build or update of the ad-hoc signed app, which should happen when a message
    /// is sent, not at launch.
    static func hasKey(for provider: AssistantProvider) -> Bool {
        var query = baseQuery(provider)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Saves `key`, or removes the stored one when it is empty.
    @discardableResult
    static func setKey(_ key: String, for provider: AssistantProvider) -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(baseQuery(provider) as CFDictionary)
        guard !key.isEmpty else { return true }
        var item = baseQuery(provider)
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrLabel as String] = "Hashline – \(provider.displayName) API key"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func baseQuery(_ provider: AssistantProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrSynchronizable as String: false,
        ]
    }
}
