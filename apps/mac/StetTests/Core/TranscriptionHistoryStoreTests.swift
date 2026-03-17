#if os(macOS)
import Foundation
import Testing

@testable import Stet

@MainActor
@Suite("Mac OpenAI Settings View Model", .serialized)
struct MacOpenAISettingsViewModelTests {
    @Test func loadReadsStoredValues() throws {
        let defaults = TestSupport.makeUserDefaults()
        let secretStore = TestSecretStore()
        try secretStore.saveString("gsk-live", forAccount: "groq.api_key")
        defaults.set(DictationProvider.groq.rawValue, forKey: MacPreferences.transcriptionProvider)
        defaults.set(true, forKey: MacPreferences.rewriteEnabled)
        defaults.set(
            TranslationTargetLanguage.german.rawValue,
            forKey: MacPreferences.translationTargetLanguage
        )
        defaults.set(false, forKey: MacPreferences.translateSelectedTextOnTranslationHotkey)

        let viewModel = MacOpenAISettingsViewModel(
            settingsStore: DictationSettingsStore(defaults: defaults, secretStore: secretStore)
        )

        viewModel.load()

        #expect(viewModel.provider == .groq)
        #expect(viewModel.rewriteEnabled)
        #expect(viewModel.translationTargetLanguage == .german)
        #expect(!viewModel.translateSelectedTextOnTranslationHotkey)
        #expect(viewModel.apiKey == "gsk-live")
        #expect(viewModel.connectionStatusText == "Configured")
    }

    @Test func switchingProviderLoadsProviderSpecificCredential() throws {
        let defaults = TestSupport.makeUserDefaults()
        let secretStore = TestSecretStore()
        try secretStore.saveString("sk-openai", forAccount: "openai.api_key")
        try secretStore.saveString("gsk-groq", forAccount: "groq.api_key")

        let viewModel = MacOpenAISettingsViewModel(
            settingsStore: DictationSettingsStore(defaults: defaults, secretStore: secretStore)
        )
        viewModel.load()

        viewModel.provider = .groq

        #expect(defaults.string(forKey: MacPreferences.transcriptionProvider) == DictationProvider.groq.rawValue)
        #expect(viewModel.apiKey == "gsk-groq")
        #expect(viewModel.credentialFieldTitle == "Groq API key")
    }

    @Test func saveCredentialTrimsAndPersistsKey() throws {
        let defaults = TestSupport.makeUserDefaults()
        let secretStore = TestSecretStore()
        let store = DictationSettingsStore(defaults: defaults, secretStore: secretStore)
        let viewModel = MacOpenAISettingsViewModel(settingsStore: store)

        viewModel.load()
        viewModel.apiKey = "  sk-live  "
        viewModel.saveCredential()

        #expect(store.loadOpenAIAPIKey() == "sk-live")
        #expect(viewModel.connectionStatusText == "Configured")

        viewModel.clearCredential()
        #expect(store.loadOpenAIAPIKey().isEmpty)
        #expect(viewModel.connectionStatusText == "Missing Key")
    }
}
#endif
