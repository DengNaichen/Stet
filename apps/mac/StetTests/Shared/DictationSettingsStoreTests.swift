import AppKit
import Carbon
import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Dictation Settings Store")
struct DictationSettingsStoreTests {
    @Test func wordsNormalizesWhitespaceAndDeduplicatesCaseInsensitively() {
        let words = DictationSettingsStore.words(
            from: " OpenAI  \nopenai,  Naicheng Deng,\nNaicheng   Deng  , Groq "
        )

        #expect(words == ["OpenAI", "Naicheng Deng", "Groq"])
    }

    @Test func loadSnapshotReturnsExpectedDefaults() {
        let defaults = TestSupport.makeUserDefaults()
        let store = DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())

        let snapshot = store.loadSnapshot()

        #expect(snapshot.provider == .openAI)
        #expect(snapshot.isRewriteEnabled == false)
        #expect(snapshot.translationTargetLanguage == .english)
        #expect(snapshot.personalDictionary.isEmpty)
        #expect(snapshot.openAIConfiguration == nil)
        #expect(snapshot.proxySettings.mode == .system)
    }

    @Test func appBranchRulesAndProxySettingsRoundTrip() throws {
        let defaults = TestSupport.makeUserDefaults()
        let store = DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
        let rule = AppBranchRule(
            name: "Docs",
            prompt: "Write for {{APP_NAME}} on {{URL}}",
            promptDelivery: .systemPrompt,
            appTargets: [.init(bundleID: "com.apple.Safari", displayName: "Safari")],
            urlPatterns: ["https://docs.example.com/"],
            isEnabled: true
        )

        defaults.set(NetworkProxyMode.custom.rawValue, forKey: MacPreferences.proxyMode)
        defaults.set(CustomProxyScheme.socks5.rawValue, forKey: MacPreferences.customProxyScheme)
        defaults.set("127.0.0.1", forKey: MacPreferences.customProxyHost)
        defaults.set("1080", forKey: MacPreferences.customProxyPort)
        store.saveAppBranchRules([rule])

        let loadedRule = try #require(store.loadAppBranchRules().first)
        let proxy = store.loadProxySettings()

        #expect(loadedRule.name == "Docs")
        #expect(loadedRule.urlPatterns == ["docs.example.com/*"])
        #expect(proxy.mode == .custom)
        #expect(proxy.customScheme == .socks5)
        #expect(proxy.customHost == "127.0.0.1")
        #expect(proxy.customPort == 1080)
    }

    @Test func translationAndHistorySettingsRoundTrip() {
        let defaults = TestSupport.makeUserDefaults()
        let store = DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())

        store.saveTranslationTargetLanguage(.japanese)
        store.saveTranslateSelectedTextOnTranslationHotkey(false)
        store.saveHistoryRetentionPeriod(.forever)
        store.savePreferredAudioInputDeviceID(123)
        store.savePersonalDictionary([" OpenAI ", "groq", "Groq"])

        #expect(store.loadTranslationTargetLanguage() == .japanese)
        #expect(store.loadTranslateSelectedTextOnTranslationHotkey() == false)
        #expect(store.loadHistoryRetentionPeriod() == .forever)
        #expect(store.loadPreferredAudioInputDeviceID() == 123)
        #expect(store.loadPersonalDictionary() == ["OpenAI", "groq"])
    }

    @Test func openAIAPIKeyUsesInjectedSecretStore() throws {
        let defaults = TestSupport.makeUserDefaults()
        let secretStore = TestSecretStore()
        let store = DictationSettingsStore(defaults: defaults, secretStore: secretStore)

        try store.saveOpenAIAPIKey("  sk-secret  ")
        #expect(store.loadOpenAIAPIKey() == "sk-secret")

        try store.saveOpenAIAPIKey("   ")
        #expect(store.loadOpenAIAPIKey().isEmpty)
    }

    @Test func providerCredentialsAreStoredSeparately() throws {
        let defaults = TestSupport.makeUserDefaults()
        let secretStore = TestSecretStore()
        let store = DictationSettingsStore(defaults: defaults, secretStore: secretStore)

        try store.saveAPIKey("sk-openai", for: .openAI)
        try store.saveAPIKey("gsk-groq", for: .groq)

        #expect(store.loadAPIKey(for: .openAI) == "sk-openai")
        #expect(store.loadAPIKey(for: .groq) == "gsk-groq")
    }

    @Test func loadSnapshotBuildsOpenAIConfigurationFromStoredValues() throws {
        let defaults = TestSupport.makeUserDefaults()
        let secretStore = TestSecretStore()
        try secretStore.saveString("sk-live", forAccount: "openai.api_key")
        defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.transcriptionProvider)
        defaults.set(true, forKey: MacPreferences.rewriteEnabled)
        defaults.set(TranslationTargetLanguage.german.rawValue, forKey: MacPreferences.translationTargetLanguage)

        let store = DictationSettingsStore(defaults: defaults, secretStore: secretStore)
        let snapshot = store.loadSnapshot()

        let configuration = try #require(snapshot.openAIConfiguration)
        #expect(snapshot.provider == .openAI)
        #expect(snapshot.isRewriteEnabled)
        #expect(snapshot.translationTargetLanguage == .german)
        #expect(configuration.apiKey == "sk-live")
        #expect(configuration.baseURL.absoluteString == "https://api.openai.com/v1")
        #expect(configuration.translationModel == "gpt-5-mini")
    }

    @Test func loadSnapshotBuildsGroqConfigurationFromStoredValues() throws {
        let defaults = TestSupport.makeUserDefaults()
        let secretStore = TestSecretStore()
        try secretStore.saveString("gsk-live", forAccount: "groq.api_key")
        defaults.set(DictationProvider.groq.rawValue, forKey: MacPreferences.transcriptionProvider)

        let store = DictationSettingsStore(defaults: defaults, secretStore: secretStore)
        let snapshot = store.loadSnapshot()

        let configuration = try #require(snapshot.openAIConfiguration)
        #expect(snapshot.provider == .groq)
        #expect(configuration.apiKey == "gsk-live")
        #expect(configuration.baseURL.absoluteString == "https://api.groq.com/openai/v1")
        #expect(configuration.transcriptionModel == "whisper-large-v3-turbo")
        #expect(configuration.translationModel == "llama-3.3-70b-versatile")
    }
}
