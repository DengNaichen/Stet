import Foundation
import Combine
import Security
import StetAI
import StetCore
import StetRewrite

/// iOS-local credential and preference storage for AI rewrite.
/// Independent from macOS `DictationSettingsStore`.
@MainActor
final class RewriteSettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let rewriteEnabled = "rewrite.enabled"
        static let selectedProvider = "rewrite.provider"
        static let selectedModel = "rewrite.model"
    }

    @Published var isRewriteEnabled: Bool {
        didSet { defaults.set(isRewriteEnabled, forKey: Keys.rewriteEnabled) }
    }

    @Published var selectedProvider: DictationProvider {
        didSet { defaults.set(selectedProvider.rawValue, forKey: Keys.selectedProvider) }
    }

    @Published var selectedModel: String {
        didSet { defaults.set(selectedModel, forKey: Keys.selectedModel) }
    }

    init() {
        self.isRewriteEnabled = defaults.bool(forKey: Keys.rewriteEnabled)
        if let raw = defaults.string(forKey: Keys.selectedProvider),
           let provider = DictationProvider(rawValue: raw) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .openAI
        }
        self.selectedModel = defaults.string(forKey: Keys.selectedModel)
            ?? DictationProviderDefaults.rewriteModel(for: .openAI)
    }

    // MARK: - Keychain API Key Storage

    func saveAPIKey(_ key: String, for provider: DictationProvider) {
        let account = "rewrite.apikey.\(provider.rawValue)"
        let data = Data(key.utf8)

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard !key.isEmpty else { return }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: kCFBooleanTrue,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func loadAPIKey(for provider: DictationProvider) -> String? {
        let account = "rewrite.apikey.\(provider.rawValue)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Service Factory

    /// Build a `TextRewriteService` if rewrite is enabled and API key is present.
    func makeRewriteServiceIfEnabled() -> (any TextRewriteService)? {
        guard isRewriteEnabled else { return nil }
        guard let apiKey = loadAPIKey(for: selectedProvider), !apiKey.isEmpty else { return nil }

        let config = DictationProviderConfigurationResolver.rewriteConfiguration(
            provider: selectedProvider,
            apiKey: apiKey,
            customModel: selectedModel
        )

        switch config.backend {
        case .remote:
            return OpenAIRewriteService(configuration: config, session: .shared)
        case .anthropic(let key):
            return AnthropicRewriteService(apiKey: key, model: config.model)
        case .google(let key):
            return GoogleRewriteService(apiKey: key, model: config.model)
        case .appleIntelligence:
            return nil // Not available on iOS through this path
        }
    }
}
