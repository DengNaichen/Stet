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
        static let customBaseURL = "rewrite.customBaseURL"
        static let customModelID = "rewrite.customModelID"
        static let customDiscoveredModels = "rewrite.customDiscoveredModels"
    }

    @Published var isRewriteEnabled: Bool {
        didSet { defaults.set(isRewriteEnabled, forKey: Keys.rewriteEnabled) }
    }

    @Published var selectedProvider: DictationProvider {
        didSet { defaults.set(selectedProvider.rawValue, forKey: Keys.selectedProvider) }
    }

    @Published var selectedModel: RewriteModel {
        didSet { defaults.set(selectedModel.rawValue, forKey: Keys.selectedModel) }
    }

    @Published var customBaseURL: String {
        didSet { defaults.set(customBaseURL, forKey: Keys.customBaseURL) }
    }

    @Published var customModelID: String {
        didSet { defaults.set(customModelID, forKey: Keys.customModelID) }
    }

    @Published var discoveredCustomModels: [String] {
        didSet { defaults.set(discoveredCustomModels, forKey: Keys.customDiscoveredModels) }
    }

    init() {
        self.isRewriteEnabled = defaults.bool(forKey: Keys.rewriteEnabled)

        let provider: DictationProvider
        if let raw = defaults.string(forKey: Keys.selectedProvider),
            let p = DictationProvider(rawValue: raw),
            p != .groq, p != .doubao, p != .anthropic
        {
            provider = p
        } else {
            provider = .openAI
        }
        self.selectedProvider = provider

        if let raw = defaults.string(forKey: Keys.selectedModel),
            let model = RewriteModel(rawValue: raw),
            RewriteModel.availableModels(for: provider).contains(model)
        {
            self.selectedModel = model
        } else {
            self.selectedModel = RewriteModel.default(for: provider)
        }

        self.customBaseURL = defaults.string(forKey: Keys.customBaseURL) ?? ""
        self.customModelID = defaults.string(forKey: Keys.customModelID) ?? ""
        self.discoveredCustomModels = defaults.stringArray(forKey: Keys.customDiscoveredModels) ?? []
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
            kSecAttrSynchronizable as String: true,
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

    /// Build a `TextRewriteService` if rewrite is enabled and the selected provider is ready.
    func makeRewriteServiceIfEnabled() -> (any TextRewriteService)? {
        guard isRewriteEnabled else { return nil }

        if selectedProvider == .custom {
            guard let baseURL = try? OpenAICompatibleBaseURL.normalize(customBaseURL) else { return nil }
            let modelID = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modelID.isEmpty else { return nil }
            let config = DictationProviderConfigurationResolver.rewriteConfiguration(
                provider: .custom,
                apiKey: loadAPIKey(for: .custom) ?? "",
                customModel: modelID,
                baseURL: baseURL
            )
            return OpenAIRewriteService(configuration: config, session: .shared)
        }

        guard let apiKey = loadAPIKey(for: selectedProvider), !apiKey.isEmpty else { return nil }

        let config = DictationProviderConfigurationResolver.rewriteConfiguration(
            provider: selectedProvider,
            apiKey: apiKey,
            customModel: selectedModel.rawValue
        )

        switch config.backend {
        case .remote:
            return OpenAIRewriteService(configuration: config, session: .shared)
        case .anthropic(let key):
            return AnthropicRewriteService(apiKey: key, model: config.model)
        case .google(let key):
            return GoogleRewriteService(apiKey: key, model: config.model)
        case .appleIntelligence:
            return nil  // Not available on iOS through this path
        }
    }
}
