#if os(macOS)

    import Foundation
    import Combine
    import StetCore
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Onboarding View Model", .serialized)
    struct OnboardingViewModelTests {
        @Test func testLanguageSelectionUpdatesRouting() async throws {
            let defaults = TestSupport.makeUserDefaults()
            let secretStore = TestSecretStore()
            let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: secretStore)
            let coordinator = MockOnboardingCoordinator(step: .language)
            let viewModel = OnboardingViewModel(
                coordinator: coordinator,
                settingsStore: settingsStore
            )

            #expect(viewModel.transcriptionPrimaryLanguage == "en")
            #expect(viewModel.transcriptionEngine == .funASRNano)

            viewModel.transcriptionPrimaryLanguage = "is"
            #expect(viewModel.transcriptionEngine == .funASRNano)

            viewModel.transcriptionSecondaryLanguage = "zh-Hans"
            #expect(viewModel.transcriptionEngine == .funASRNano)

            viewModel.transcriptionPrimaryLanguage = "en"
            #expect(viewModel.transcriptionEngine == .funASRNano)
        }

        @Test func testEnginePreparationFlow() async throws {
            let defaults = TestSupport.makeUserDefaults()
            let secretStore = TestSecretStore()
            let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: secretStore)
            let coordinator = MockOnboardingCoordinator(step: .language)
            let modelsDirectory = TestSupport.temporaryDirectoryURL()
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            for asset in FunASRNanoModelAsset.allCases {
                try Data("model".utf8).write(to: modelsDirectory.appendingPathComponent(asset.fileName))
            }

            let viewModel = OnboardingViewModel(
                coordinator: coordinator,
                settingsStore: settingsStore,
                funASRNanoModelManager: FunASRNanoModelManager(
                    modelsDirectoryProvider: { modelsDirectory }
                )
            )

            #expect(viewModel.engineDownloadState == .idle)

            await viewModel.handleEngineDownloadPrimaryAction()

            #expect(viewModel.engineDownloadState == .ready)
            #expect(settingsStore.loadTranscriptionEngine() == .funASRNano)
        }
    }

#endif
