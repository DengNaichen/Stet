import Foundation
import Security

public protocol DictationSecretStore: Sendable {
    nonisolated func loadString(forAccount account: String) throws -> String?
    nonisolated func saveString(_ value: String, forAccount account: String) throws
    nonisolated func deleteString(forAccount account: String) throws
}

public enum SecretStoreError: LocalizedError, Sendable {
    case unexpectedStatus(OSStatus)

    public nonisolated var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain request failed with status \(status)."
        }
    }
}

public enum DictationCredentialAccount {
    public static func apiKey(for provider: DictationProvider) -> String {
        provider == .appleIntelligence ? "apple_intelligence.local" : "\(provider.rawValue).api_key"
    }

    public static func legacyIOSAPIKey(for provider: DictationProvider) -> String {
        "rewrite.apikey.\(provider.rawValue)"
    }
}

public struct LegacyKeychainLookup: Sendable {
    public let service: String?
    public let account: String
    public let useDataProtectionKeychain: Bool
    public let synchronizable: Bool?

    public init(service: String?, account: String, useDataProtectionKeychain: Bool, synchronizable: Bool? = nil) {
        self.service = service
        self.account = account
        self.useDataProtectionKeychain = useDataProtectionKeychain
        self.synchronizable = synchronizable
    }

    var query: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: useDataProtectionKeychain,
        ]
        query[kSecAttrService as String] = service
        if let synchronizable {
            query[kSecAttrSynchronizable as String] = synchronizable
        } else if useDataProtectionKeychain {
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        }
        return query
    }
}

public struct SharedKeychainSecretStore: DictationSecretStore {
    private let serviceName: String
    private let accessGroup: String?
    private let legacyLookups: @Sendable (String) -> [LegacyKeychainLookup]

    public init(
        serviceName: String = StetCloudSyncConfiguration.sharedKeychainService,
        accessGroup: String? = StetCloudSyncConfiguration.sharedKeychainAccessGroup,
        legacyLookups: @escaping @Sendable (String) -> [LegacyKeychainLookup] = { _ in [] }
    ) {
        self.serviceName = serviceName
        self.accessGroup = accessGroup
        self.legacyLookups = legacyLookups
    }

    public static func macOS(
        legacyBundleIdentifiers: [String] = [
            Bundle.main.bundleIdentifier, "NaichengDeng.Stet", "NaichengDeng.Stet.Debug",
        ]
        .compactMap { $0 }
    ) -> Self {
        Self { account in
            var seen = Set<String>()
            return legacyBundleIdentifiers.filter { seen.insert($0).inserted }.flatMap { service in
                [true, false].map {
                    LegacyKeychainLookup(service: service, account: account, useDataProtectionKeychain: $0)
                }
            }
        }
    }

    public static func iOS() -> Self {
        Self { account in
            guard
                let provider = DictationProvider.allCases.first(where: {
                    DictationCredentialAccount.apiKey(for: $0) == account
                })
            else { return [] }
            return [
                LegacyKeychainLookup(
                    service: nil, account: DictationCredentialAccount.legacyIOSAPIKey(for: provider),
                    useDataProtectionKeychain: true)
            ]
        }
    }

    func query(forAccount account: String, synchronizable: Bool?) -> [String: Any] {
        var query = LegacyKeychainLookup(
            service: serviceName, account: account,
            useDataProtectionKeychain: true, synchronizable: synchronizable
        ).query
        query[kSecAttrAccessGroup as String] = accessGroup
        return query
    }

    func writeAttributes(_ value: String) -> [String: Any] {
        [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock, kSecValueData as String: Data(value.utf8)]
    }

    public func loadString(forAccount account: String) throws -> String? {
        for sync in [true, false] {
            do {
                if let value = try read(query(forAccount: account, synchronizable: sync)) { return value }
            } catch SecretStoreError.unexpectedStatus(let status)
                where status == errSecMissingEntitlement || (sync && status == errSecNotAvailable)
            {
                continue
            }
        }
        for legacy in legacyLookups(account) {
            do {
                if let value = try read(legacy.query), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if (try? saveString(value, forAccount: account)) != nil {
                        try? delete(legacy.query)
                    }
                    return value
                }
            } catch SecretStoreError.unexpectedStatus(let status)
                where status == errSecMissingEntitlement || status == errSecNotAvailable
                || status == errSecInteractionNotAllowed
            {
                continue
            }
        }
        return nil
    }

    private func read(_ attributes: [String: Any]) throws -> String? {
        var query = attributes
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecretStoreError.unexpectedStatus(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.unexpectedStatus(errSecDecode)
        }
        return value
    }

    public func saveString(_ value: String, forAccount account: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try deleteString(forAccount: account) }
        let local = query(forAccount: account, synchronizable: false)
        do {
            try upsert(trimmed, matching: query(forAccount: account, synchronizable: true))
        } catch SecretStoreError.unexpectedStatus(errSecNotAvailable) {
            try upsert(trimmed, matching: local)
            return
        }
        try delete(local)
    }

    private func upsert(_ value: String, matching query: [String: Any]) throws {
        let attributes = writeAttributes(value)
        let add = query.merging(attributes) { _, new in new }
        var status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        }
        guard status == errSecSuccess else { throw SecretStoreError.unexpectedStatus(status) }
    }

    public func deleteString(forAccount account: String) throws {
        defer {
            for legacy in legacyLookups(account) { try? delete(legacy.query) }
        }
        try delete(query(forAccount: account, synchronizable: nil))
    }

    private func delete(_ query: [String: Any]) throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(status)
        }
    }
}
