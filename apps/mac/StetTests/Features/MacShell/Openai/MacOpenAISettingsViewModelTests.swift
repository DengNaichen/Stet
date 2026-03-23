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
        defaults.set(AIExecutionMode.managed.rawValue, forKey: MacPreferences.aiExecutionMode)
        defaults.set(DictationProvider.groq.rawValue, forKey: MacPreferences.transcriptionProvider)
        defaults.set(true, forKey: MacPreferences.rewriteEnabled)
        defaults.set(
            DictationLanguageMode.mixedChineseEnglish.rawValue,
            forKey: MacPreferences.dictationLanguageMode
        )

        let viewModel = MacOpenAISettingsViewModel(
            settingsStore: DictationSettingsStore(defaults: defaults, secretStore: secretStore),
            relaySessionProvider: { true }
        )

        viewModel.load()

        #expect(viewModel.executionMode == .managed)
        #expect(viewModel.provider == .groq)
        #expect(viewModel.rewriteEnabled)
        #expect(viewModel.dictationLanguageMode == .mixedChineseEnglish)
        #expect(viewModel.apiKey == "gsk-live")
        #expect(viewModel.connectionStatusText == "Relay Only")
    }

    @Test func switchingProviderLoadsProviderSpecificCredential() throws {
        let defaults = TestSupport.makeUserDefaults()
        let secretStore = TestSecretStore()
        try secretStore.saveString("sk-openai", forAccount: "openai.api_key")
        try secretStore.saveString("gsk-groq", forAccount: "groq.api_key")

        let viewModel = MacOpenAISettingsViewModel(
            settingsStore: DictationSettingsStore(defaults: defaults, secretStore: secretStore),
            relaySessionProvider: { false }
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
        let viewModel = MacOpenAISettingsViewModel(settingsStore: store, relaySessionProvider: { false })

        viewModel.load()
        viewModel.apiKey = "  sk-live  "
        viewModel.saveCredential()

        #expect(store.loadOpenAIAPIKey() == "sk-live")
        #expect(viewModel.connectionStatusText == "Direct Fallback")

        viewModel.clearCredential()
        #expect(store.loadOpenAIAPIKey().isEmpty)
        #expect(viewModel.connectionStatusText == "Missing Key")
    }

    @Test func changingExecutionModePersistsSelection() {
        let defaults = TestSupport.makeUserDefaults()
        let viewModel = MacOpenAISettingsViewModel(
            settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore()),
            relaySessionProvider: { false }
        )

        viewModel.load()
        viewModel.executionMode = .byok

        #expect(defaults.string(forKey: MacPreferences.aiExecutionMode) == AIExecutionMode.byok.rawValue)
    }

    @Test func managedModeWithoutRelaySessionShowsSignInRequired() {
        let defaults = TestSupport.makeUserDefaults()
        defaults.set(AIExecutionMode.managed.rawValue, forKey: MacPreferences.aiExecutionMode)

        let viewModel = MacOpenAISettingsViewModel(
            settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore()),
            relaySessionProvider: { false }
        )

        viewModel.load()

        #expect(viewModel.connectionStatusText == "Sign In Required")
        #expect(viewModel.connectionNeedsAttention)
        #expect(viewModel.missingCredentialMessage == "Sign in with your Stet account to use Managed Relay for dictation.")
    }

    @Test func automaticModeWithRelaySessionShowsRelayActiveWithoutKey() {
        let defaults = TestSupport.makeUserDefaults()
        let viewModel = MacOpenAISettingsViewModel(
            settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore()),
            relaySessionProvider: { true }
        )

        viewModel.load()

        #expect(viewModel.connectionStatusText == "Relay Active")
        #expect(!viewModel.connectionNeedsAttention)
        #expect(viewModel.missingCredentialMessage == nil)
    }
}
#endif
