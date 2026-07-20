import Combine
import Foundation
import Security

nonisolated enum FunASRRegion: String, CaseIterable, Identifiable, Sendable {
    case beijing
    case singapore

    var id: Self { self }

    var displayName: String {
        switch self {
        case .beijing:
            "Beijing"
        case .singapore:
            "Singapore"
        }
    }

    fileprivate var endpointRegion: String {
        switch self {
        case .beijing:
            "cn-beijing"
        case .singapore:
            "ap-southeast-1"
        }
    }
}

nonisolated struct FunASRConfiguration: Equatable, Sendable {
    let region: FunASRRegion
    let workspaceID: String
    let apiKey: String

    init(region: FunASRRegion, workspaceID: String, apiKey: String) throws {
        let workspaceID = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidWorkspaceID(workspaceID) else {
            throw FunASRConfigurationError.invalidWorkspaceID
        }
        guard !apiKey.isEmpty else {
            throw FunASRConfigurationError.missingAPIKey
        }

        self.region = region
        self.workspaceID = workspaceID
        self.apiKey = apiKey
    }

    var endpoint: URL {
        URL(
            string:
                "wss://\(workspaceID).\(region.endpointRegion).maas.aliyuncs.com/api-ws/v1/inference"
        )!
    }

    var webSocketRequest: URLRequest {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func isValidWorkspaceID(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            (65...90).contains(scalar.value)
                || (97...122).contains(scalar.value)
                || (48...57).contains(scalar.value)
                || scalar.value == 45
        }
    }
}

nonisolated enum FunASRConfigurationError: LocalizedError, Equatable {
    case invalidWorkspaceID
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidWorkspaceID:
            "Enter a Workspace ID containing only letters, numbers, and hyphens."
        case .missingAPIKey:
            "Enter a FunASR API key first."
        }
    }
}

protocol FunASRCredentialStoring {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ apiKey: String) throws
}

struct FunASRKeychainCredentialStore: FunASRCredentialStoring {
    static let service = "com.openwhispr.StetMobile.funasr"
    static let account = "api-key"

    private let service: String
    private let account: String

    init(service: String = Self.service, account: String = Self.account) {
        self.service = service
        self.account = account
    }

    func loadAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data,
            let apiKey = String(data: data, encoding: .utf8)
        else {
            throw FunASRKeychainError.loadFailed
        }
        return apiKey
    }

    func saveAPIKey(_ apiKey: String) throws {
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        if apiKey.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw FunASRKeychainError.saveFailed
            }
            return
        }

        let data = Data(apiKey.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw FunASRKeychainError.saveFailed
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw FunASRKeychainError.saveFailed
        }
    }
}

private enum FunASRKeychainError: LocalizedError {
    case loadFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .loadFailed:
            "The FunASR API key could not be read securely."
        case .saveFailed:
            "The FunASR API key could not be saved securely."
        }
    }
}

@MainActor
final class FunASRSettingsStore: ObservableObject {
    @Published var region: FunASRRegion {
        didSet { defaults.set(region.rawValue, forKey: Self.regionKey) }
    }

    @Published var workspaceID: String {
        didSet { defaults.set(workspaceID, forKey: Self.workspaceIDKey) }
    }

    private static let regionKey = "funasr.region"
    private static let workspaceIDKey = "funasr.workspaceID"

    private let defaults: UserDefaults
    private let credentialStore: any FunASRCredentialStoring

    init(
        defaults: UserDefaults = .standard,
        credentialStore: (any FunASRCredentialStoring)? = nil
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore ?? FunASRKeychainCredentialStore()
        region = defaults.string(forKey: Self.regionKey)
            .flatMap(FunASRRegion.init(rawValue:)) ?? .beijing
        workspaceID = defaults.string(forKey: Self.workspaceIDKey) ?? ""
    }

    func loadAPIKey() throws -> String {
        try credentialStore.loadAPIKey() ?? ""
    }

    func saveAPIKey(_ apiKey: String) throws {
        try credentialStore.saveAPIKey(apiKey)
    }

    func configuration(apiKey: String? = nil) throws -> FunASRConfiguration {
        try FunASRConfiguration(
            region: region,
            workspaceID: workspaceID,
            apiKey: apiKey ?? loadAPIKey()
        )
    }
}
