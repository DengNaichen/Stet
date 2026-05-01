import Foundation
import Security

enum SecretStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }

            return "Keychain request failed with status \(status)."
        }
    }
}

struct KeychainSecretStore: Sendable {
    private let serviceName: String

    nonisolated init(serviceName: String = Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet") {
        self.serviceName = serviceName
    }

    nonisolated func loadString(forAccount account: String) throws -> String? {
        var query = baseQuery(forAccount: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw SecretStoreError.unexpectedStatus(status)
        }
    }

    nonisolated func saveString(_ value: String, forAccount account: String) throws {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedValue.isEmpty {
            try deleteString(forAccount: account)
            return
        }

        let data = Data(trimmedValue.utf8)
        let query = baseQuery(forAccount: account)
        let updateAttributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrSynchronizable as String] = kCFBooleanTrue
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

            guard addStatus == errSecSuccess else {
                throw SecretStoreError.unexpectedStatus(addStatus)
            }
        default:
            throw SecretStoreError.unexpectedStatus(updateStatus)
        }
    }

    nonisolated func deleteString(forAccount account: String) throws {
        let status = SecItemDelete(baseQuery(forAccount: account) as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(status)
        }
    }

    nonisolated private func baseQuery(forAccount account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }
}
