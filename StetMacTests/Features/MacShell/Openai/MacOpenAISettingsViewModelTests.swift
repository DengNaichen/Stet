#if os(macOS)
    import Foundation
    import StetAI
    import StetCore
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
            defaults.set(DictationProvider.groq.rawValue, forKey: MacPreferences.transcriptionProvider)
            defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.rewriteProvider)
            defaults.set(true, forKey: MacPreferences.rewriteEnabled)

            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: secretStore)
            )

            viewModel.load()

            #expect(viewModel.rewriteProvider == .openAI)
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

        @Test func byokRequiresOnlyRewriteProviderKey() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(DictationProvider.groq.rawValue, forKey: MacPreferences.transcriptionProvider)
            defaults.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.rewriteProvider)
            defaults.set(true, forKey: MacPreferences.rewriteEnabled)

            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
            )

            viewModel.load()

            #expect(viewModel.connectionNeedsAttention)
            #expect(viewModel.visibleCredentialProviders == [.openAI])
            #expect(
                viewModel.missingCredentialMessage
                    == "Add OpenAI API key before using transcript improvement.")
        }

        @Test func appleIntelligenceRewriteDoesNotRequireCredential() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(DictationProvider.appleIntelligence.rawValue, forKey: MacPreferences.rewriteProvider)
            defaults.set(true, forKey: MacPreferences.rewriteEnabled)

            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
            )

            viewModel.load()

            #expect(viewModel.unifiedProvider == .appleIntelligence)
            #expect(viewModel.visibleCredentialProviders.isEmpty)
            #expect(viewModel.missingCredentialMessage == nil)
        }

        @Test func groqIsHiddenFromRewritePickerAndMigratesToOpenAI() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(DictationProvider.groq.rawValue, forKey: MacPreferences.rewriteProvider)
            defaults.set(true, forKey: MacPreferences.rewriteEnabled)

            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
            )

            viewModel.load()

            #expect(viewModel.rewriteProvider == .openAI)
            #expect(viewModel.selectedModel == .gpt56Luna)
            #expect(!MacOpenAISettingsViewModel.UnifiedAIProvider.allCases.map(\.rawValue).contains("groq"))
            #expect(!MacOpenAISettingsViewModel.UnifiedAIProvider.allCases.map(\.rawValue).contains("doubao"))
            #expect(!MacOpenAISettingsViewModel.UnifiedAIProvider.allCases.map(\.rawValue).contains("anthropic"))
            #expect(defaults.string(forKey: MacPreferences.rewriteProvider) == DictationProvider.openAI.rawValue)
        }

        @Test func anthropicIsHiddenFromRewritePickerAndMigratesToOpenAI() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(DictationProvider.anthropic.rawValue, forKey: MacPreferences.rewriteProvider)
            defaults.set(true, forKey: MacPreferences.rewriteEnabled)

            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
            )

            viewModel.load()

            #expect(viewModel.rewriteProvider == .openAI)
            #expect(viewModel.selectedModel == .gpt56Luna)
            #expect(!MacOpenAISettingsViewModel.UnifiedAIProvider.allCases.map(\.rawValue).contains("anthropic"))
            #expect(defaults.string(forKey: MacPreferences.rewriteProvider) == DictationProvider.openAI.rawValue)
        }

        @Test func doubaoIsHiddenFromRewritePickerAndMigratesToOpenAI() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(DictationProvider.doubao.rawValue, forKey: MacPreferences.rewriteProvider)
            defaults.set(true, forKey: MacPreferences.rewriteEnabled)

            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
            )

            viewModel.load()

            #expect(viewModel.rewriteProvider == .openAI)
            #expect(viewModel.selectedModel == .gpt56Luna)
            #expect(!MacOpenAISettingsViewModel.UnifiedAIProvider.allCases.map(\.rawValue).contains("doubao"))
            #expect(defaults.string(forKey: MacPreferences.rewriteProvider) == DictationProvider.openAI.rawValue)
        }

        @Test func deepSeekRewriteIsSelectableAndUsesV4Models() {
            let defaults = TestSupport.makeUserDefaults()
            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
            )

            viewModel.load()
            viewModel.unifiedProvider = .deepSeek

            #expect(viewModel.rewriteProvider == .deepSeek)
            #expect(viewModel.unifiedProvider == .deepSeek)
            #expect(viewModel.selectedModel == .deepseekV4Flash)
            #expect(viewModel.availableModels == [.deepseekV4Flash])
            #expect(viewModel.visibleCredentialProviders == [.deepSeek])
        }

        @Test func loadRespectsStoredRewriteDisabledValue() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(false, forKey: MacPreferences.rewriteEnabled)

            let store = DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())

            #expect(!store.loadRewriteEnabled())
        }

        @Test func customProviderIsSelectableAndDoesNotRequireAPIKey() {
            let defaults = TestSupport.makeUserDefaults()
            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore())
            )

            viewModel.load()
            viewModel.unifiedProvider = .custom
            viewModel.customBaseURL = "http://127.0.0.1:11434"
            viewModel.customModelID = "llama3.1"

            #expect(viewModel.rewriteProvider == .custom)
            #expect(viewModel.unifiedProvider == .custom)
            #expect(viewModel.visibleCredentialProviders.isEmpty)
            #expect(viewModel.availableModels.isEmpty)
            #expect(viewModel.missingCredentialMessage == nil)
            #expect(!viewModel.connectionNeedsAttention)
            #expect(defaults.string(forKey: MacPreferences.rewriteProvider) == DictationProvider.custom.rawValue)
            #expect(defaults.string(forKey: MacPreferences.customRewriteBaseURL) == "http://127.0.0.1:11434")
            #expect(defaults.string(forKey: MacPreferences.customRewriteModelID) == "llama3.1")
        }

        @Test func customProviderSnapshotAllowsEmptyAPIKeyWhenURLAndModelAreSet() {
            let defaults = TestSupport.makeUserDefaults()
            defaults.set(DictationProvider.custom.rawValue, forKey: MacPreferences.rewriteProvider)
            defaults.set(true, forKey: MacPreferences.rewriteEnabled)
            defaults.set("http://127.0.0.1:11434", forKey: MacPreferences.customRewriteBaseURL)
            defaults.set("llama3.1", forKey: MacPreferences.customRewriteModelID)

            let snapshot = DictationSettingsStore(
                defaults: defaults,
                secretStore: TestSecretStore()
            ).loadSnapshot()

            #expect(snapshot.rewriteProvider == .custom)
            #expect(snapshot.rewriteProviderConfiguration?.provider == .custom)
            #expect(snapshot.rewriteProviderConfiguration?.model == "llama3.1")
            #expect(snapshot.requiredProviderRequirements().isEmpty)

            if case .remote(let endpoint) = snapshot.rewriteProviderConfiguration?.backend {
                #expect(endpoint.apiKey.isEmpty)
                #expect(endpoint.baseURL.absoluteString == "http://127.0.0.1:11434/v1")
            } else {
                Issue.record("Expected a remote custom rewrite configuration")
            }
        }

        @Test func customProviderProbeFillsDiscoveredModelsAndDefaultSelection() async {
            let defaults = TestSupport.makeUserDefaults()
            let viewModel = MacOpenAISettingsViewModel(
                settingsStore: DictationSettingsStore(defaults: defaults, secretStore: TestSecretStore()),
                modelProbe: StubModelProbe(models: ["gpt-4o-mini", "llama3.1"])
            )

            viewModel.load()
            viewModel.unifiedProvider = .custom
            viewModel.customBaseURL = "https://openrouter.ai/api/v1"
            viewModel.customAPIKey = "sk-live"

            await viewModel.loadCustomModels()

            #expect(viewModel.discoveredCustomModels == ["gpt-4o-mini", "llama3.1"])
            #expect(viewModel.customModelID == "gpt-4o-mini")
            #expect(viewModel.customModelProbeState == .loaded(2))
            #expect(
                defaults.stringArray(forKey: MacPreferences.customRewriteDiscoveredModels) == [
                    "gpt-4o-mini", "llama3.1",
                ])
        }
    }

    private struct StubModelProbe: OpenAICompatibleModelProbing {
        let models: [String]

        func listModels(baseURL: URL, apiKey: String) async throws -> [String] {
            models
        }
    }
#endif
