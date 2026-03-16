import Foundation

protocol DictationSecretStore: Sendable {
    nonisolated func loadString(forAccount account: String) throws -> String?
    nonisolated func saveString(_ value: String, forAccount account: String) throws
    nonisolated func deleteString(forAccount account: String) throws
}

extension KeychainSecretStore: DictationSecretStore {}

struct DictationSettingsSnapshot: Sendable {
    let provider: DictationProvider
    let isRewriteEnabled: Bool
    let shouldPauseMediaDuringDictation: Bool
    let preferredAudioInputDeviceID: UInt32?
    let openAIConfiguration: OpenAIConfiguration?
    let translationTargetLanguage: TranslationTargetLanguage
    let translateSelectedTextOnTranslationHotkey: Bool
    let personalDictionary: [String]
    let interactionSoundsEnabled: Bool
    let interactionSoundPreset: InteractionSoundPreset
    let proxySettings: NetworkProxySettings

    var isOpenAIConfigured: Bool {
        openAIConfiguration != nil
    }
}

struct DictationSettingsStore: Sendable {
    private enum SecretKey {
        nonisolated static let openAIAPIKey = "openai.api_key"
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
        let providerRawValue = defaults.string(forKey: MacPreferences.transcriptionProvider) ?? ""
        let provider = DictationProvider(rawValue: providerRawValue) ?? .openAI
        let isRewriteEnabled = defaults.object(forKey: MacPreferences.rewriteEnabled) as? Bool ?? false
        let shouldPauseMediaDuringDictation =
            defaults.object(forKey: MacPreferences.pauseMediaDuringDictation) as? Bool ?? false
        let preferredAudioInputDeviceID = loadPreferredAudioInputDeviceID()
        let apiKey = loadOpenAIAPIKey().trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = loadOpenAIBaseURL()
        let providerDefaults = OpenAIConfiguration.providerDefaults(for: baseURL)
        let translationModel = loadOpenAITranslationModel(
            providerDefault: providerDefaults.translationModel,
            isGroqBaseURL: OpenAIConfiguration.isGroqBaseURL(baseURL)
        )
        let translationTargetLanguage = loadTranslationTargetLanguage()
        let translateSelectedTextOnTranslationHotkey = loadTranslateSelectedTextOnTranslationHotkey()
        let personalDictionary = loadPersonalDictionaryEnabled() ? loadPersonalDictionary() : []
        let interactionSoundsEnabled =
            defaults.object(forKey: MacPreferences.interactionSoundsEnabled) as? Bool ?? true
        let interactionSoundPreset = loadInteractionSoundPreset()
        let proxySettings = loadProxySettings()

        let configuration: OpenAIConfiguration? = apiKey.isEmpty
            ? nil
            : OpenAIConfiguration(
                apiKey: apiKey,
                baseURL: baseURL,
                transcriptionModel: providerDefaults.transcriptionModel,
                translationModel: translationModel,
                rewriteModel: providerDefaults.rewriteModel
            )

        return DictationSettingsSnapshot(
            provider: provider,
            isRewriteEnabled: isRewriteEnabled,
            shouldPauseMediaDuringDictation: shouldPauseMediaDuringDictation,
            preferredAudioInputDeviceID: preferredAudioInputDeviceID,
            openAIConfiguration: configuration,
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

    nonisolated func saveTranslationTargetLanguage(_ language: TranslationTargetLanguage) {
        defaults.set(language.rawValue, forKey: MacPreferences.translationTargetLanguage)
    }

    nonisolated func loadOpenAITranslationModel(
        providerDefault: String = "gpt-5-mini",
        isGroqBaseURL: Bool = false
    ) -> String {
        let rawValue = defaults.string(forKey: MacPreferences.openAITranslationModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let rawValue, !rawValue.isEmpty else {
            return providerDefault
        }

        // Treat the old OpenAI default as a placeholder when the user switches to Groq.
        if isGroqBaseURL, rawValue == "gpt-5-mini" {
            return providerDefault
        }

        return rawValue
    }

    nonisolated func loadOpenAIBaseURL() -> URL {
        let rawValue = defaults.string(forKey: MacPreferences.openAIBaseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let rawValue, !rawValue.isEmpty else {
            return URL(string: "https://api.openai.com/v1")!
        }

        guard let parsed = URL(string: rawValue), parsed.scheme != nil else {
            return URL(string: "https://api.openai.com/v1")!
        }

        return parsed
    }

    nonisolated func saveOpenAIBaseURL(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            defaults.set("https://api.openai.com/v1", forKey: MacPreferences.openAIBaseURL)
            return
        }

        defaults.set(trimmed, forKey: MacPreferences.openAIBaseURL)
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

    nonisolated func loadPreferredAudioInputDeviceID() -> UInt32? {
        let value = defaults.integer(forKey: MacPreferences.selectedAudioInputDeviceID)
        return value > 0 ? UInt32(value) : nil
    }

    nonisolated func savePreferredAudioInputDeviceID(_ deviceID: UInt32?) {
        defaults.set(Int(deviceID ?? 0), forKey: MacPreferences.selectedAudioInputDeviceID)
    }

    nonisolated func loadProxySettings() -> NetworkProxySettings {
        NetworkProxySettings(
            mode: .system,
            customScheme: .http,
            customHost: "",
            customPort: nil
        )
    }

    nonisolated static func words(from rawInput: String) -> [String] {
        DictionaryModel.words(from: rawInput)
    }

    nonisolated func loadOpenAIAPIKey() -> String {
        (try? secretStore.loadString(forAccount: SecretKey.openAIAPIKey)) ?? ""
    }

    nonisolated func saveOpenAIAPIKey(_ apiKey: String) throws {
        try secretStore.saveString(apiKey, forAccount: SecretKey.openAIAPIKey)
    }
}
