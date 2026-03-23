import Foundation

protocol DictationSecretStore: Sendable {
    nonisolated func loadString(forAccount account: String) throws -> String?
    nonisolated func saveString(_ value: String, forAccount account: String) throws
    nonisolated func deleteString(forAccount account: String) throws
}

extension KeychainSecretStore: DictationSecretStore {}

struct DictationSettingsSnapshot: Sendable {
    let provider: DictationProvider
    let executionMode: AIExecutionMode
    let isRewriteEnabled: Bool
    let dictationLanguageMode: DictationLanguageMode
    let shouldPauseMediaDuringDictation: Bool
    let providerConfiguration: OpenAIConfiguration?
    let personalDictionary: [String]
    let interactionSoundsEnabled: Bool
    let interactionSoundPreset: InteractionSoundPreset

    var hasLocalProviderConfiguration: Bool {
        providerConfiguration != nil
    }
}

struct DictationSettingsStore: Sendable {
    private enum SecretKey {
        nonisolated static func apiKey(for provider: DictationProvider) -> String {
            switch provider {
            case .openAI:
                return "openai.api_key"
            case .groq:
                return "groq.api_key"
            }
        }
    }

    private let defaultsStore: UserDefaultsStore
    private let secretStore: any DictationSecretStore
    private let dictionaryModel: DictionaryModel

    nonisolated init() {
        self.init(
            defaults: .standard,
            secretStore: KeychainSecretStore(),
            dictionaryModel: nil
        )
    }

    nonisolated init(
        defaults: UserDefaults,
        secretStore: any DictationSecretStore,
        dictionaryModel: DictionaryModel? = nil
    ) {
        self.defaultsStore = UserDefaultsStore(defaults)
        self.secretStore = secretStore
        self.dictionaryModel = dictionaryModel ?? DictionaryModel(defaults: defaults)
    }

    nonisolated func loadSnapshot() -> DictationSettingsSnapshot {
        let provider = loadProvider()
        let executionMode = loadExecutionMode()
        let isRewriteEnabled = loadRewriteEnabled()
        let dictationLanguageMode = loadDictationLanguageMode()
        let shouldPauseMediaDuringDictation =
            defaultsStore.object(forKey: MacPreferences.pauseMediaDuringDictation) as? Bool ?? false
        let apiKey = loadAPIKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        let personalDictionary = loadPersonalDictionaryEnabled() ? loadPersonalDictionary() : []
        let interactionSoundsEnabled =
            defaultsStore.object(forKey: MacPreferences.interactionSoundsEnabled) as? Bool ?? true
        let interactionSoundPreset = loadInteractionSoundPreset()

        let configuration: OpenAIConfiguration? = apiKey.isEmpty
            ? nil
            : OpenAIConfiguration(apiKey: apiKey, provider: provider)

        return DictationSettingsSnapshot(
            provider: provider,
            executionMode: executionMode,
            isRewriteEnabled: isRewriteEnabled,
            dictationLanguageMode: dictationLanguageMode,
            shouldPauseMediaDuringDictation: shouldPauseMediaDuringDictation,
            providerConfiguration: configuration,
            personalDictionary: personalDictionary,
            interactionSoundsEnabled: interactionSoundsEnabled,
            interactionSoundPreset: interactionSoundPreset
        )
    }

    nonisolated func loadPersonalDictionary() -> [String] {
        dictionaryModel.loadEntries()
    }

    nonisolated func loadPersonalDictionaryEnabled() -> Bool {
        dictionaryModel.loadIsEnabled()
    }

    nonisolated func savePersonalDictionary(_ words: [String]) {
        dictionaryModel.saveEntries(words)
    }

    nonisolated func savePersonalDictionaryEnabled(_ enabled: Bool) {
        dictionaryModel.saveIsEnabled(enabled)
    }

    nonisolated func loadInteractionSoundPreset() -> InteractionSoundPreset {
        InteractionSoundPreset.defaultPreset
    }

    nonisolated func loadProvider() -> DictationProvider {
        let rawValue = defaultsStore.string(forKey: MacPreferences.transcriptionProvider) ?? ""
        return DictationProvider(rawValue: rawValue) ?? .openAI
    }

    nonisolated func loadExecutionMode() -> AIExecutionMode {
        let rawValue = defaultsStore.string(forKey: MacPreferences.aiExecutionMode) ?? ""
        return AIExecutionMode(rawValue: rawValue) ?? .automatic
    }

    nonisolated func saveProvider(_ provider: DictationProvider) {
        defaultsStore.set(provider.rawValue, forKey: MacPreferences.transcriptionProvider)
    }

    nonisolated func saveExecutionMode(_ mode: AIExecutionMode) {
        defaultsStore.set(mode.rawValue, forKey: MacPreferences.aiExecutionMode)
    }

    nonisolated func loadRewriteEnabled() -> Bool {
        defaultsStore.object(forKey: MacPreferences.rewriteEnabled) as? Bool ?? false
    }

    nonisolated func saveRewriteEnabled(_ enabled: Bool) {
        defaultsStore.set(enabled, forKey: MacPreferences.rewriteEnabled)
    }

    nonisolated func loadDictationLanguageMode() -> DictationLanguageMode {
        let rawValue = defaultsStore.string(forKey: MacPreferences.dictationLanguageMode) ?? ""
        return DictationLanguageMode(rawValue: rawValue) ?? .automatic
    }

    nonisolated func saveDictationLanguageMode(_ mode: DictationLanguageMode) {
        defaultsStore.set(mode.rawValue, forKey: MacPreferences.dictationLanguageMode)
    }

    nonisolated func loadHotkeyDistinguishModifierSides() -> Bool {
        defaultsStore.object(forKey: MacPreferences.hotkeyDistinguishModifierSides) as? Bool ?? false
    }

    nonisolated func saveHotkeyDistinguishModifierSides(_ enabled: Bool) {
        defaultsStore.set(enabled, forKey: MacPreferences.hotkeyDistinguishModifierSides)
    }

    nonisolated static func words(from rawInput: String) -> [String] {
        DictionaryModel.words(from: rawInput)
    }

    nonisolated func loadAPIKey(for provider: DictationProvider) -> String {
        (try? secretStore.loadString(forAccount: SecretKey.apiKey(for: provider))) ?? ""
    }

    nonisolated func saveAPIKey(_ apiKey: String, for provider: DictationProvider) throws {
        try secretStore.saveString(apiKey, forAccount: SecretKey.apiKey(for: provider))
    }

    nonisolated func loadOpenAIAPIKey() -> String {
        loadAPIKey(for: .openAI)
    }

    nonisolated func saveOpenAIAPIKey(_ apiKey: String) throws {
        try saveAPIKey(apiKey, for: .openAI)
    }
}
