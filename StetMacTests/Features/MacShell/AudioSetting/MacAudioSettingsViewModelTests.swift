#if os(macOS)
    import StetCore
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Mac Audio Settings View Model", .serialized)
    struct MacAudioSettingsViewModelTests {
        @Test func exposesAllThreeLocalTranscriptionEngines() {
            let viewModel = MacAudioSettingsViewModel()

            #expect(
                viewModel.localTranscriptionEngineOptions == [
                    .fluidAudio,
                    .localWhisper,
                    .sherpaOnnxSenseVoice,
                ]
            )
        }

        @Test func loadsAndPersistsSelectedLocalTranscriptionEngine() {
            let defaults = TestSupport.makeUserDefaults()
            let settingsStore = DictationSettingsStore(
                defaults: defaults,
                secretStore: TestSecretStore()
            )
            settingsStore.saveTranscriptionEngine(.localWhisper)
            let viewModel = MacAudioSettingsViewModel(
                settingsStore: settingsStore,
                configuration: UserDefaultsModelStorage(defaults: defaults)
            )

            viewModel.onAppear()
            defer { viewModel.onDisappear() }

            #expect(viewModel.localTranscriptionEngine == .localWhisper)
            #expect(settingsStore.loadTranscriptionEngine() == .localWhisper)

            viewModel.localTranscriptionEngine = .fluidAudio

            #expect(settingsStore.loadTranscriptionEngine() == .fluidAudio)
        }
    }
#endif
