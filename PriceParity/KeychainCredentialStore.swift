import Foundation
import Security

enum KeychainCredentialStore {
    private static let service = "com.maicolcabreja.PriceParity.credentials"
    private static let account = "asc-api"

    static func save(_ credentials: StoredASCKeyCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [String: Any] = baseQuery
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            try validate(SecItemAdd(addQuery as CFDictionary, nil))
            return
        }

        try validate(status)
    }

    static func load() throws -> StoredASCKeyCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        try validate(status)

        guard let data = item as? Data else {
            return nil
        }

        return try JSONDecoder().decode(StoredASCKeyCredentials.self, from: data)
    }

    static func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            try validate(status)
            return
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }

    private static func validate(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: keychainMessage(for: status)
            ])
        }
    }

    private static func keychainMessage(for status: OSStatus) -> String {
        switch status {
        case errSecAuthFailed:
            return "The app could not access the saved credentials."
        case errSecDuplicateItem:
            return "The credential record already exists."
        case errSecInteractionNotAllowed:
            return "The device is locked, so the saved credentials cannot be read yet."
        default:
            return "Keychain operation failed with status \(status)."
        }
    }
}
