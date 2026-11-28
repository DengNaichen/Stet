import Combine
import Foundation
import StetAI
import StetCore

/// iOS-local preference storage paired with the shared iCloud Keychain secret store for AI rewrite.
@MainActor
final class RewriteSettingsStore: ObservableObject {
    let catalogStore: RewriteModelCatalogStore
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

    private var modelKey: String { "\(Keys.selectedModel).\(selectedProvider.rawValue)" }

    var selectedModelID: String {
        catalogStore.catalog.resolvedModelID(for: selectedProvider, preferredID: defaults.string(forKey: modelKey))
            ?? ""
    }

    func selectModel(_ id: String) {
        guard catalogStore.catalog.model(for: selectedProvider, modelID: id) != nil else { return }
        objectWillChange.send()
        defaults.set(id, forKey: modelKey)
    }

    private var thinkingKey: String { "rewrite.thinkingLevel.\(selectedProvider.rawValue).\(selectedModelID)" }
    var thinkingLevel: RewriteThinkingLevel? {
        catalogStore.catalog.resolvedThinkingLevel(
            for: selectedProvider, modelID: selectedModelID,
            preferredLevel: defaults.string(forKey: thinkingKey).flatMap(RewriteThinkingLevel.init(rawValue:)))
    }

    func selectThinkingLevel(_ level: RewriteThinkingLevel) {
        guard
            catalogStore.catalog.availableThinkingLevels(for: selectedProvider, modelID: selectedModelID).contains(
                level)
        else { return }
        objectWillChange.send()
        defaults.set(level.rawValue, forKey: thinkingKey)
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
        secretStore: any DictationSecretStore = SharedKeychainSecretStore.iOS(),
        catalogStore: RewriteModelCatalogStore? = nil
    ) {
        self.catalogStore = catalogStore ?? .shared
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

        if let legacy = defaults.string(forKey: Keys.selectedModel) {
            let key = "\(Keys.selectedModel).\(provider.rawValue)"
            if defaults.object(forKey: key) == nil { defaults.set(legacy, forKey: key) }
            defaults.removeObject(forKey: Keys.selectedModel)
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

    func configurationIfEnabled() -> RewriteProviderConfiguration? {
        guard isRewriteEnabled, selectedProvider != .appleIntelligence else { return nil }
        return DictationProviderConfigurationResolver.resolve(
            provider: selectedProvider, apiKey: loadAPIKey(for: selectedProvider) ?? "",
            preferredModelID: selectedModelID, preferredThinkingLevel: thinkingLevel,
            customBaseURL: customBaseURL, customModelID: customModelID, catalog: catalogStore.catalog)
    }
}
