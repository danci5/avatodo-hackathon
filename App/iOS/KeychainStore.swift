import Foundation
import Security

enum KeychainStore {
    private static let service = "app.avatodo.meta"
    static func load() throws -> String? {
        var item: CFTypeRef?
        let result = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: "meta", kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne
        ] as CFDictionary, &item)
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { throw KeychainError.unavailable(result) }
        return key
    }
    static func save(_ key: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.allSatisfy({ (33...126).contains($0) }) else { throw KeychainError.invalid }
        let identity: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "meta"]
        let attributes: [CFString: Any] = [kSecValueData: Data(value.utf8), kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let updated = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            let added = SecItemAdd(identity.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError.unavailable(added) }
        } else if updated != errSecSuccess { throw KeychainError.unavailable(updated) }
    }
    static func remove() throws {
        let result = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "meta"] as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw KeychainError.unavailable(result) }
    }
}

enum KeychainError: Error, LocalizedError {
    case unavailable(OSStatus), invalid
    var errorDescription: String? {
        switch self {
        case let .unavailable(status): "Secure storage is unavailable (\(status)). Unlock this iPhone and try again."
        case .invalid: "Enter a valid Meta API key."
        }
    }
}
