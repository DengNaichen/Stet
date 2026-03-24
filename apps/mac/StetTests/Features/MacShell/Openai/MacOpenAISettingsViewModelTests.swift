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
            try secretStore.saveString("sk-openai", forAccount: "openai.api_key")
            try secretStore.saveString("gsk-live", forAccount: "groq.api_key")
            defaults.set(AIExecutionMode.managed.rawValue, forKey: MacPreferences.aiExecutionMode)
            defaults.set(DictationProvider.groq.rawValue, forKey: MacPreferences.transcriptionProvider)
            defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.rewriteProvider)
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
            #expect(viewModel.transcriptionProvider == .groq)
            #expect(viewModel.rewriteProvider == .openAI)
            #expect(viewModel.dictationLanguageMode == .mixedChineseEnglish)
            #expect(viewModel.groqAPIKey == "gsk-live")
            #expect(viewModel.openAIAPIKey == "sk-openai")
        }

        @Test func changingTranscriptionProviderDefaultsRewriteProviderUntilExplicitlyChanged() throws {
            let defaults = TestSupport.makeUserDefaults()
            let secretStore = TestSecretStore()

            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: secretStore),
                relaySessionProvider: { false }
            )
            viewModel.load()

            viewModel.transcriptionProvider = .groq

            #expect(defaults.string(forKey: MacPreferences.transcriptionProvider) == DictationProvider.groq.rawValue)
            #expect(defaults.string(forKey: MacPreferences.rewriteProvider) == DictationProvider.groq.rawValue)
            #expect(viewModel.rewriteProvider == .groq)
        }

        @Test func explicitRewriteProviderSelectionPersistsIndependently() throws {
            let defaults = TestSupport.makeUserDefaults()
            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore()),
                relaySessionProvider: { false }
            )

            viewModel.load()
            viewModel.transcriptionProvider = .groq
            viewModel.rewriteProvider = .openAI

            #expect(defaults.string(forKey: MacPreferences.transcriptionProvider) == DictationProvider.groq.rawValue)
            #expect(defaults.string(forKey: MacPreferences.rewriteProvider) == DictationProvider.openAI.rawValue)
        }

        @Test func saveCredentialTrimsAndPersistsKeyPerProvider() throws {
            let defaults = TestSupport.makeUserDefaults()
            let secretStore = TestSecretStore()
            let store = DictationSettingsStore(defaults: defaults, secretStore: secretStore)
            let viewModel = MacOpenAISettingsViewModel(settingsStore: store, relaySessionProvider: { false })

            viewModel.load()
            viewModel.setAPIKey("  sk-live  ", for: .openAI)
            viewModel.saveCredential(for: .openAI)
            viewModel.setAPIKey("  gsk-live  ", for: .groq)
            viewModel.saveCredential(for: .groq)

            #expect(store.loadOpenAIAPIKey() == "sk-live")
            #expect(store.loadAPIKey(for: .groq) == "gsk-live")
            viewModel.clearCredential(for: .openAI)
            #expect(store.loadOpenAIAPIKey().isEmpty)
            #expect(viewModel.openAIAPIKey.isEmpty)
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

        @Test func managedModeWithoutRelaySessionHidesDirectConfiguration() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(AIExecutionMode.managed.rawValue, forKey: MacPreferences.aiExecutionMode)

            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore()),
                relaySessionProvider: { false }
            )

            viewModel.load()

            #expect(viewModel.connectionNeedsAttention)
            #expect(viewModel.missingCredentialMessage == nil)
            #expect(!viewModel.showsProviderConfiguration)
            #expect(viewModel.visibleCredentialProviders.isEmpty)
        }

        @Test func automaticModeWithRelaySessionDoesNotNeedCredentialMessage() {
            let defaults = TestSupport.makeUserDefaults()
            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore()),
                relaySessionProvider: { true }
            )

            viewModel.load()

            #expect(!viewModel.connectionNeedsAttention)
            #expect(viewModel.missingCredentialMessage == nil)
        }

        @Test func byokMixedProvidersRequireBothKeys() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(AIExecutionMode.byok.rawValue, forKey: MacPreferences.aiExecutionMode)
            defaults.set(DictationProvider.groq.rawValue, forKey: MacPreferences.transcriptionProvider)
            defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.rewriteProvider)
            defaults.set(true, forKey: MacPreferences.rewriteEnabled)

            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore()),
                relaySessionProvider: { false }
            )

            viewModel.load()

            #expect(viewModel.connectionNeedsAttention)
            #expect(viewModel.visibleCredentialProviders == [.openAI, .groq])
            #expect(
                viewModel.missingCredentialMessage
                    == "Add OpenAI and Groq API keys before using direct transcription or transcript improvement.")
        }

        @Test func unsupportedProviderPairShowsConfigurationWarningWithoutStatusSurface() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(AIExecutionMode.byok.rawValue, forKey: MacPreferences.aiExecutionMode)
            defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.transcriptionProvider)
            defaults.set(DictationProvider.groq.rawValue, forKey: MacPreferences.rewriteProvider)
            defaults.set(true, forKey: MacPreferences.rewriteEnabled)

            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore()),
                relaySessionProvider: { false }
            )

            viewModel.load()

            #expect(viewModel.connectionNeedsAttention)
            #expect(
                viewModel.missingCredentialMessage
                    == "OpenAI transcription with Groq rewrite is not supported as a default BYOK pair on Mac.")
        }

        @Test func managedModeWithRelaySessionHidesDirectConfigurationUI() throws {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(AIExecutionMode.managed.rawValue, forKey: MacPreferences.aiExecutionMode)
            defaults.set(DictationProvider.groq.rawValue, forKey: MacPreferences.transcriptionProvider)
            defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.rewriteProvider)
            defaults.set(true, forKey: MacPreferences.rewriteEnabled)

            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore()),
                relaySessionProvider: { true }
            )

            viewModel.load()

            #expect(!viewModel.showsProviderConfiguration)
            #expect(viewModel.visibleCredentialProviders.isEmpty)
        }

        @Test func loadTreatsStoredRewriteDisabledValueAsEnabledForRuntime() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(false, forKey: MacPreferences.rewriteEnabled)

            let store = DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())

            #expect(store.loadRewriteEnabled())
        }
    }
#endif
