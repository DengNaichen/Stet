#if os(macOS)
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Mac OpenAI Settings View Model", .serialized)
    struct MacOpenAISettingsViewModelTests {
        @Test func executionModesExposeOnlyManagedAndByok() {
            #expect(AIExecutionMode.allCases == [.managed, .byok])
        }

        @Test func loadExecutionModeFallsBackToByokForUnknownValue() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set("automatic", forKey: MacPreferences.aiExecutionMode)
            let store = DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())

            #expect(store.loadExecutionMode() == .byok)
        }

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
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: secretStore)
            )

            viewModel.load()

            #expect(viewModel.executionMode == .managed)
            #expect(viewModel.rewriteProvider == .openAI)
            #expect(viewModel.dictationLanguageMode == .mixedChineseEnglish)
            #expect(viewModel.groqAPIKey == "gsk-live")
            #expect(viewModel.openAIAPIKey == "sk-openai")
        }

        @Test func explicitRewriteProviderSelectionPersistsIndependently() throws {
            let defaults = TestSupport.makeUserDefaults()
            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
            )
            viewModel.load()
            viewModel.rewriteProvider = .openAI

            #expect(defaults.string(forKey: MacPreferences.rewriteProvider) == DictationProvider.openAI.rawValue)
        }

        @Test func saveCredentialTrimsAndPersistsKeyPerProvider() throws {
            let defaults = TestSupport.makeUserDefaults()
            let secretStore = TestSecretStore()
            let store = DictationSettingsStore(defaults: defaults, secretStore: secretStore)
            let viewModel = MacOpenAISettingsViewModel(settingsStore: store)

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
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
            )

            viewModel.load()
            viewModel.executionMode = .byok

            #expect(defaults.string(forKey: MacPreferences.aiExecutionMode) == AIExecutionMode.byok.rawValue)
        }

        @Test func managedModeShowsSignInMessageAndHidesDirectConfiguration() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(AIExecutionMode.managed.rawValue, forKey: MacPreferences.aiExecutionMode)

            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
            )

            viewModel.load()

            #expect(viewModel.connectionNeedsAttention)
            #expect(viewModel.missingCredentialMessage == "Sign in to use Stet account dictation.")
            #expect(viewModel.visibleCredentialProviders.isEmpty)
        }

        @Test func byokRequiresOnlyRewriteProviderKey() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(AIExecutionMode.byok.rawValue, forKey: MacPreferences.aiExecutionMode)
            defaults.set(DictationProvider.groq.rawValue, forKey: MacPreferences.transcriptionProvider)
            defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.rewriteProvider)
            defaults.set(true, forKey: MacPreferences.rewriteEnabled)

            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore()),
                localWhisperModelManager: LocalWhisperModelManager(
                    modelsDirectoryProvider: { TestSupport.temporaryDirectoryURL("local-whisper-settings") },
                    runtimeAvailableProvider: { true }
                )
            )

            viewModel.load()

            #expect(viewModel.connectionNeedsAttention)
            #expect(viewModel.visibleCredentialProviders == [.openAI])
            #expect(
                viewModel.missingCredentialMessage
                    == "Add OpenAI API key before using transcript improvement.")
        }

        @Test func localWhisperStatusShowsExpectedModelPathWhenRuntimeAvailableButModelMissing() {
            let defaults = TestSupport.makeUserDefaults()
            let modelsDirectory = TestSupport.temporaryDirectoryURL("local-whisper-settings-path")
            let expectedModelPath = modelsDirectory.appendingPathComponent("ggml-large-v3-turbo-q5_0.bin").path

            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore()),
                localWhisperModelManager: LocalWhisperModelManager(
                    modelsDirectoryProvider: { modelsDirectory },
                    runtimeAvailableProvider: { true }
                )
            )

            viewModel.load()

            #expect(viewModel.connectionNeedsAttention)
            #expect(
                viewModel.localWhisperStatusMessage
                    == "Place ggml-large-v3-turbo-q5_0.bin at \(expectedModelPath).")
        }

        @Test func localWhisperStatusShowsRuntimeUnavailableWhenEngineMissing() {
            let defaults = TestSupport.makeUserDefaults()
            let modelsDirectory = TestSupport.temporaryDirectoryURL("local-whisper-settings-runtime")

            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore()),
                localWhisperModelManager: LocalWhisperModelManager(
                    modelsDirectoryProvider: { modelsDirectory },
                    runtimeAvailableProvider: { false }
                )
            )

            viewModel.load()

            #expect(viewModel.localWhisperNeedsAttention)
            #expect(viewModel.localWhisperStatusMessage.contains("Local Whisper runtime is not linked") == true)
        }

        @Test func loadRespectsStoredRewriteDisabledValue() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(false, forKey: MacPreferences.rewriteEnabled)

            let store = DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())

            #expect(!store.loadRewriteEnabled())
        }
    }
#endif
