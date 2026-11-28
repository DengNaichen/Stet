import Combine
import Foundation
import StetAI
import StetCore
import StetRewrite

/// iOS-local preference storage paired with the shared iCloud Keychain secret store for AI rewrite.
@MainActor
final class RewriteSettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private let secretStore: any DictationSecretStore

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

    @Published private(set) var lastKeychainError: String?

    init(
        defaults: UserDefaults = .standard,
        secretStore: any DictationSecretStore = SharedKeychainSecretStore.iOS()
    ) {
        self.defaults = defaults
        self.secretStore = secretStore
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

    func saveAPIKey(_ key: String, for provider: DictationProvider) throws {
        let account = DictationCredentialAccount.apiKey(for: provider)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try secretStore.deleteString(forAccount: account)
            } else {
                try secretStore.saveString(trimmed, forAccount: account)
            }
            lastKeychainError = nil
        } catch {
            lastKeychainError = error.localizedDescription
            throw error
        }
    }

    func loadAPIKey(for provider: DictationProvider) -> String? {
        let account = DictationCredentialAccount.apiKey(for: provider)
        do {
            let value = try secretStore.loadString(forAccount: account)
            lastKeychainError = nil
            return value
        } catch {
            lastKeychainError = error.localizedDescription
            return nil
        }
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
            customModel: resolvedModelID(for: selectedProvider, selectedModel: selectedModel),
            thinkingLevel: defaultThinkingLevel(for: selectedProvider)
        )

        switch config.backend {
        case .remote:
            return OpenAIRewriteService(configuration: config, session: .shared)
        case .anthropic(let key):
            return AnthropicRewriteService(apiKey: key, model: config.model)
        case .google(let key):
            return GoogleRewriteService(
                apiKey: key,
                model: config.model,
                thinkingLevel: config.thinkingLevel
            )
        case .appleIntelligence:
            return nil  // Not available on iOS through this path
        }
    }

    private func resolvedModelID(for provider: DictationProvider, selectedModel: RewriteModel) -> String {
        switch provider {
        case .deepSeek where selectedModel == .deepseekV4Flash:
            return "deepseek-flash"
        case .google where selectedModel == .gemini37Flash:
            return "gemini-3.8-flash"
        default:
            return selectedModel.rawValue
        }
    }

    private func defaultThinkingLevel(for provider: DictationProvider) -> RewriteThinkingLevel? {
        switch provider {
        case .deepSeek:
            return .off
        case .openAI:
            return .minimal
        case .google:
            return .low
        default:
            return nil
        }
    }
}
