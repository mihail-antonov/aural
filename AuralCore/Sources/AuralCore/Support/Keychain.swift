import Foundation
import Security

public enum KeychainError: Error, Equatable {
    case notFound(service: String)
    case unreadable(service: String)
    /// Any other Security framework error (`OSStatus`).
    case failure(status: Int32)
}

/// Minimal wrapper around the macOS Keychain for generic passwords
/// (the Soloist API key, later Web API tokens).
public enum Keychain {
    /// Reads the password stored under `service`.
    /// The first read by a new binary may show a macOS "allow access" prompt.
    public static func readPassword(service: String) throws(KeychainError) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        // `SecItemCopyMatching` writes the result into an untyped "out" parameter
        // (`inout AnyObject?`), so we cast it to `Data` afterwards.
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
                throw .unreadable(service: service)
            }
            return password.trimmingCharacters(in: .whitespacesAndNewlines)
        case errSecItemNotFound:
            throw .notFound(service: service)
        default:
            Log.keychain.error("Keychain read failed for \(service, privacy: .public): \(status)")
            throw .failure(status: status)
        }
    }

    /// Stores `password` under `service`, replacing any existing value.
    public static func savePassword(_ password: String, service: String) throws(KeychainError) {
        try deletePassword(service: service)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrLabel as String: "Aural – Soloist API key",
            kSecValueData as String: Data(password.utf8),
            // Readable once the Mac has been unlocked after a restart; never synced.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            Log.keychain.error("Keychain save failed for \(service, privacy: .public): \(status)")
            throw .failure(status: status)
        }
    }

    /// Removes the value stored under `service`. Succeeds if there is none.
    public static func deletePassword(service: String) throws(KeychainError) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Log.keychain.error("Keychain delete failed for \(service, privacy: .public): \(status)")
            throw .failure(status: status)
        }
    }
}
