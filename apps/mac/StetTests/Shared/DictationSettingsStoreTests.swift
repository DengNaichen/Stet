import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Dictation Settings Store")
struct DictationSettingsStoreTests {
    private func makeStore(
        defaults: UserDefaults,
        secretStore: any DictationSecretStore = TestSecretStore()
    ) -> DictationSettingsStore {
        let dictionaryModel = DictionaryModel(
            modelContainer: try! DictionaryModel.makeInMemoryModelContainer(),
            defaults: defaults
        )
        return DictationSettingsStore(
            defaults: defaults,
            secretStore: secretStore,
            dictionaryModel: dictionaryModel
        )
    }

    @Test func wordsNormalizesWhitespaceAndDeduplicatesCaseInsensitively() {
        let words = DictationSettingsStore.words(
            from: " OpenAI  \nopenai,  Naicheng Deng,\nNaicheng   Deng  , Groq "
        )

        #expect(words == ["OpenAI", "Naicheng Deng", "Groq"])
    }

    @Test func loadSnapshotReturnsExpectedDefaults() {
        let defaults = TestSupport.makeUserDefaults()
        let store = makeStore(defaults: defaults)

        let snapshot = store.loadSnapshot()

        #expect(snapshot.provider == .openAI)
        #expect(snapshot.executionMode == .automatic)
        #expect(snapshot.isRewriteEnabled == false)
        #expect(snapshot.translationTargetLanguage == .english)
        #expect(snapshot.personalDictionary.isEmpty)
        #expect(snapshot.providerConfiguration == nil)
    }

    @Test func translationAndDictionarySettingsRoundTrip() {
        let defaults = TestSupport.makeUserDefaults()
        let store = makeStore(defaults: defaults)

        store.saveExecutionMode(.managed)
        store.saveTranslationTargetLanguage(.japanese)
        store.saveTranslateSelectedTextOnTranslationHotkey(false)
        store.savePersonalDictionary([" OpenAI ", "groq", "Groq"])

        #expect(store.loadExecutionMode() == .managed)
        #expect(store.loadTranslationTargetLanguage() == .japanese)
        #expect(store.loadTranslateSelectedTextOnTranslationHotkey() == false)
        #expect(store.loadPersonalDictionary() == ["OpenAI", "groq"])
    }

    @Test func openAIAPIKeyUsesInjectedSecretStore() throws {
        let defaults = TestSupport.makeUserDefaults()
        let secretStore = TestSecretStore()
        let store = makeStore(defaults: defaults, secretStore: secretStore)

        try store.saveOpenAIAPIKey("  sk-secret  ")
        #expect(store.loadOpenAIAPIKey() == "sk-secret")

        try store.saveOpenAIAPIKey("   ")
        #expect(store.loadOpenAIAPIKey().isEmpty)
    }

    @Test func providerCredentialsAreStoredSeparately() throws {
        let defaults = TestSupport.makeUserDefaults()
        let secretStore = TestSecretStore()
        let store = makeStore(defaults: defaults, secretStore: secretStore)

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
        defaults.set(AIExecutionMode.byok.rawValue, forKey: MacPreferences.aiExecutionMode)
        defaults.set(true, forKey: MacPreferences.rewriteEnabled)
        defaults.set(TranslationTargetLanguage.german.rawValue, forKey: MacPreferences.translationTargetLanguage)

        let store = makeStore(defaults: defaults, secretStore: secretStore)
        let snapshot = store.loadSnapshot()

        let configuration = try #require(snapshot.providerConfiguration)
        #expect(snapshot.provider == .openAI)
        #expect(snapshot.executionMode == .byok)
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
        defaults.set(AIExecutionMode.managed.rawValue, forKey: MacPreferences.aiExecutionMode)

        let store = makeStore(defaults: defaults, secretStore: secretStore)
        let snapshot = store.loadSnapshot()

        let configuration = try #require(snapshot.providerConfiguration)
        #expect(snapshot.provider == .groq)
        #expect(snapshot.executionMode == .managed)
        #expect(configuration.apiKey == "gsk-live")
        #expect(configuration.baseURL.absoluteString == "https://api.groq.com/openai/v1")
        #expect(configuration.transcriptionModel == "whisper-large-v3-turbo")
        #expect(configuration.translationModel == "llama-3.3-70b-versatile")
        #expect(configuration.rewriteModel == "openai/gpt-oss-120b")
    }
}
