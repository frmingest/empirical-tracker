import Foundation
import Security

/// Low-level Keychain CRUD for persisting the three session fields between launches.
/// Uses `kSecClassGenericPassword` with a fixed service identifier.
/// All operations are synchronous and safe to call from any thread.
public enum KeychainService {

    private static let service = "com.empirical.tracker"

    private enum Key {
        static let accessToken = "session.access_token"
        static let userID      = "session.user_id"
        static let email       = "session.email"
    }

    // MARK: - Public API

    public static func save(session: StoredSession) {
        write(session.accessToken, key: Key.accessToken)
        write(session.userID,      key: Key.userID)
        write(session.email,       key: Key.email)
    }

    public static func loadSession() -> StoredSession? {
        guard
            let token  = read(key: Key.accessToken),
            let userID = read(key: Key.userID),
            let email  = read(key: Key.email)
        else { return nil }
        return StoredSession(accessToken: token, userID: userID, email: email)
    }

    public static func deleteSession() {
        delete(key: Key.accessToken)
        delete(key: Key.userID)
        delete(key: Key.email)
    }

    // MARK: - Primitives

    private static func write(_ value: String, key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        let update: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData] = data
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    private static func read(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    private static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
