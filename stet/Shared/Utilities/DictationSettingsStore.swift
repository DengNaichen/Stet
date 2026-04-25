import Foundation

protocol DictationSecretStore: Sendable {
    nonisolated func loadString(forAccount account: String) throws -> String?
    nonisolated func saveString(_ value: String, forAccount account: String) throws
    nonisolated func deleteString(forAccount account: String) throws
}

extension KeychainSecretStore: DictationSecretStore {}

enum DictationPipelineStep: String, Sendable, Equatable, Hashable {
    case transcription
    case rewrite

    nonisolated var displayName: String {
        switch self {
        case .transcription:
            return "transcription"
        case .rewrite:
            return "rewrite"
        }
    }
}

struct ProviderConfigurationRequirement: Sendable, Equatable, Hashable {
    nonisolated let step: DictationPipelineStep
    nonisolated let provider: DictationProvider
}

struct DictationSettingsSnapshot: Sendable {
    let transcriptionProvider: DictationProvider
    let rewriteProvider: DictationProvider
    let isRewriteEnabled: Bool
    let dictationLanguageMode: DictationLanguageMode
    let shouldPauseMediaDuringDictation: Bool
    let transcriptionProviderConfiguration: TranscriptionProviderConfiguration?
    let rewriteProviderConfiguration: RewriteProviderConfiguration?
    let personalDictionary: [String]
    let interactionSoundsEnabled: Bool
    let interactionSoundPreset: InteractionSoundPreset

    nonisolated var provider: DictationProvider {
        transcriptionProvider
    }

    nonisolated var providerConfiguration: TranscriptionProviderConfiguration? {
        transcriptionProviderConfiguration
    }

    nonisolated var providerPair: DictationProviderPair {
        DictationProviderPair(
            transcriptionProvider: transcriptionProvider,
            rewriteProvider: rewriteProvider
        )
    }

    nonisolated var hasLocalProviderConfiguration: Bool {
        transcriptionProviderConfiguration != nil
    }

    nonisolated func requiredProviderRequirements() -> [ProviderConfigurationRequirement] {
        var requirements = [
            ProviderConfigurationRequirement(step: .transcription, provider: transcriptionProvider)
        ]

        if isRewriteEnabled {
            if rewriteProvider.requiresAPIKey {
                requirements.append(
                    ProviderConfigurationRequirement(step: .rewrite, provider: rewriteProvider)
                )
            }
        }

        return requirements
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
            case .appleIntelligence:
                return "apple_intelligence.local"
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
        let transcriptionProvider = loadTranscriptionProvider()
        let rewriteProvider = loadRewriteProvider(defaultingTo: transcriptionProvider)
        let isRewriteEnabled = loadRewriteEnabled()
        let dictationLanguageMode = loadDictationLanguageMode()
        let shouldPauseMediaDuringDictation =
            defaultsStore.object(forKey: MacPreferences.pauseMediaDuringDictation) as? Bool ?? false
        let providerPair = DictationProviderPair(
            transcriptionProvider: transcriptionProvider,
            rewriteProvider: rewriteProvider
        )
        let transcriptionAPIKey = loadAPIKey(for: transcriptionProvider)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rewriteAPIKey = loadAPIKey(for: rewriteProvider)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let personalDictionary = loadPersonalDictionaryEnabled() ? loadPersonalDictionary() : []
        let interactionSoundsEnabled =
            defaultsStore.object(forKey: MacPreferences.interactionSoundsEnabled) as? Bool ?? true
        let interactionSoundPreset = loadInteractionSoundPreset()

        let transcriptionConfiguration: TranscriptionProviderConfiguration? =
            transcriptionAPIKey.isEmpty
            ? nil
            : DictationProviderConfigurationResolver.transcriptionConfiguration(
                apiKey: transcriptionAPIKey,
                providerPair: providerPair
            )
        let rewriteConfiguration: RewriteProviderConfiguration?
        if rewriteProvider == .appleIntelligence {
            rewriteConfiguration = DictationProviderConfigurationResolver.rewriteConfiguration(
                apiKey: "",
                providerPair: providerPair
            )
        } else {
            rewriteConfiguration =
                rewriteAPIKey.isEmpty
                ? nil
                : DictationProviderConfigurationResolver.rewriteConfiguration(
                    apiKey: rewriteAPIKey,
                    providerPair: providerPair
                )
        }

        return DictationSettingsSnapshot(
            transcriptionProvider: transcriptionProvider,
            rewriteProvider: rewriteProvider,
            isRewriteEnabled: isRewriteEnabled,
            dictationLanguageMode: dictationLanguageMode,
            shouldPauseMediaDuringDictation: shouldPauseMediaDuringDictation,
            transcriptionProviderConfiguration: transcriptionConfiguration,
            rewriteProviderConfiguration: rewriteConfiguration,
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

    nonisolated func loadTranscriptionProvider() -> DictationProvider {
        let rawValue = defaultsStore.string(forKey: MacPreferences.transcriptionProvider) ?? ""
        return DictationProvider(rawValue: rawValue) ?? .openAI
    }

    nonisolated func loadRewriteProvider(defaultingTo transcriptionProvider: DictationProvider? = nil)
        -> DictationProvider
    {
        let fallbackProvider = transcriptionProvider ?? loadTranscriptionProvider()
        let rawValue = defaultsStore.string(forKey: MacPreferences.rewriteProvider) ?? ""
        return DictationProvider(rawValue: rawValue) ?? fallbackProvider
    }

    nonisolated func loadProvider() -> DictationProvider {
        loadRewriteProvider(defaultingTo: loadTranscriptionProvider())
    }

    nonisolated func saveTranscriptionProvider(_ provider: DictationProvider) {
        let previousTranscriptionProvider = loadTranscriptionProvider()
        let currentRewriteProvider = loadRewriteProvider(defaultingTo: previousTranscriptionProvider)
        defaultsStore.set(provider.rawValue, forKey: MacPreferences.transcriptionProvider)

        if defaultsStore.string(forKey: MacPreferences.rewriteProvider) == nil
            || currentRewriteProvider == previousTranscriptionProvider
        {
            defaultsStore.set(provider.rawValue, forKey: MacPreferences.rewriteProvider)
        }
    }

    nonisolated func saveRewriteProvider(_ provider: DictationProvider) {
        defaultsStore.set(provider.rawValue, forKey: MacPreferences.rewriteProvider)
    }

    nonisolated func saveProvider(_ provider: DictationProvider) {
        saveRewriteProvider(provider)
    }

    nonisolated func loadRewriteEnabled() -> Bool {
        defaultsStore.object(forKey: MacPreferences.rewriteEnabled) as? Bool ?? true
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
