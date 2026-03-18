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
    let shouldPauseMediaDuringDictation: Bool
    let providerConfiguration: OpenAIConfiguration?
    let translationTargetLanguage: TranslationTargetLanguage
    let translateSelectedTextOnTranslationHotkey: Bool
    let personalDictionary: [String]
    let interactionSoundsEnabled: Bool
    let interactionSoundPreset: InteractionSoundPreset
    let proxySettings: NetworkProxySettings

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

    nonisolated(unsafe) private let defaults: UserDefaults
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
        self.defaults = defaults
        self.secretStore = secretStore
        self.dictionaryModel = dictionaryModel ?? DictionaryModel(defaults: defaults)
    }

    nonisolated func loadSnapshot() -> DictationSettingsSnapshot {
        let provider = loadProvider()
        let executionMode = loadExecutionMode()
        let isRewriteEnabled = loadRewriteEnabled()
        let shouldPauseMediaDuringDictation =
            defaults.object(forKey: MacPreferences.pauseMediaDuringDictation) as? Bool ?? false
        let apiKey = loadAPIKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        let translationTargetLanguage = loadTranslationTargetLanguage()
        let translateSelectedTextOnTranslationHotkey = loadTranslateSelectedTextOnTranslationHotkey()
        let personalDictionary = loadPersonalDictionaryEnabled() ? loadPersonalDictionary() : []
        let interactionSoundsEnabled =
            defaults.object(forKey: MacPreferences.interactionSoundsEnabled) as? Bool ?? true
        let interactionSoundPreset = loadInteractionSoundPreset()
        let proxySettings = loadProxySettings()

        let configuration: OpenAIConfiguration? = apiKey.isEmpty
            ? nil
            : OpenAIConfiguration(apiKey: apiKey, provider: provider)

        return DictationSettingsSnapshot(
            provider: provider,
            executionMode: executionMode,
            isRewriteEnabled: isRewriteEnabled,
            shouldPauseMediaDuringDictation: shouldPauseMediaDuringDictation,
            providerConfiguration: configuration,
            translationTargetLanguage: translationTargetLanguage,
            translateSelectedTextOnTranslationHotkey: translateSelectedTextOnTranslationHotkey,
            personalDictionary: personalDictionary,
            interactionSoundsEnabled: interactionSoundsEnabled,
            interactionSoundPreset: interactionSoundPreset,
            proxySettings: proxySettings
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
        let rawValue = defaults.string(forKey: MacPreferences.interactionSoundPreset) ?? ""
        return InteractionSoundPreset(rawValue: rawValue) ?? .soft
    }

    nonisolated func loadTranslationTargetLanguage() -> TranslationTargetLanguage {
        let rawValue = defaults.string(forKey: MacPreferences.translationTargetLanguage) ?? ""
        return TranslationTargetLanguage(rawValue: rawValue) ?? .english
    }

    nonisolated func loadProvider() -> DictationProvider {
        let rawValue = defaults.string(forKey: MacPreferences.transcriptionProvider) ?? ""
        return DictationProvider(rawValue: rawValue) ?? .openAI
    }

    nonisolated func loadExecutionMode() -> AIExecutionMode {
        let rawValue = defaults.string(forKey: MacPreferences.aiExecutionMode) ?? ""
        return AIExecutionMode(rawValue: rawValue) ?? .automatic
    }

    nonisolated func saveProvider(_ provider: DictationProvider) {
        defaults.set(provider.rawValue, forKey: MacPreferences.transcriptionProvider)
    }

    nonisolated func saveExecutionMode(_ mode: AIExecutionMode) {
        defaults.set(mode.rawValue, forKey: MacPreferences.aiExecutionMode)
    }

    nonisolated func saveTranslationTargetLanguage(_ language: TranslationTargetLanguage) {
        defaults.set(language.rawValue, forKey: MacPreferences.translationTargetLanguage)
    }

    nonisolated func loadRewriteEnabled() -> Bool {
        defaults.object(forKey: MacPreferences.rewriteEnabled) as? Bool ?? false
    }

    nonisolated func saveRewriteEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: MacPreferences.rewriteEnabled)
    }

    nonisolated func loadTranslateSelectedTextOnTranslationHotkey() -> Bool {
        defaults.object(forKey: MacPreferences.translateSelectedTextOnTranslationHotkey) as? Bool ?? true
    }

    nonisolated func saveTranslateSelectedTextOnTranslationHotkey(_ enabled: Bool) {
        defaults.set(enabled, forKey: MacPreferences.translateSelectedTextOnTranslationHotkey)
    }

    nonisolated func loadHotkeyDistinguishModifierSides() -> Bool {
        defaults.object(forKey: MacPreferences.hotkeyDistinguishModifierSides) as? Bool ?? false
    }

    nonisolated func saveHotkeyDistinguishModifierSides(_ enabled: Bool) {
        defaults.set(enabled, forKey: MacPreferences.hotkeyDistinguishModifierSides)
    }

    nonisolated func loadProxySettings() -> NetworkProxySettings {
        NetworkProxySettings(
            mode: NetworkProxyMode(
                rawValue: defaults.string(forKey: MacPreferences.proxyMode) ?? ""
            ) ?? .system,
            customScheme: CustomProxyScheme(
                rawValue: defaults.string(forKey: MacPreferences.customProxyScheme) ?? ""
            ) ?? .http,
            customHost: defaults.string(forKey: MacPreferences.customProxyHost)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            customPort: loadCustomProxyPort()
        )
    }

    nonisolated func saveProxySettings(_ settings: NetworkProxySettings) {
        defaults.set(settings.mode.rawValue, forKey: MacPreferences.proxyMode)
        defaults.set(settings.customScheme.rawValue, forKey: MacPreferences.customProxyScheme)

        let trimmedHost = settings.customHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHost.isEmpty {
            defaults.removeObject(forKey: MacPreferences.customProxyHost)
        } else {
            defaults.set(trimmedHost, forKey: MacPreferences.customProxyHost)
        }

        if let port = settings.customPort, port > 0 {
            defaults.set(String(port), forKey: MacPreferences.customProxyPort)
        } else {
            defaults.removeObject(forKey: MacPreferences.customProxyPort)
        }
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

    nonisolated private func loadCustomProxyPort() -> Int? {
        if let number = defaults.object(forKey: MacPreferences.customProxyPort) as? NSNumber {
            let port = number.intValue
            return port > 0 ? port : nil
        }

        guard let rawValue = defaults.string(forKey: MacPreferences.customProxyPort)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            let port = Int(rawValue),
            port > 0 else {
            return nil
        }

        return port
    }
}
