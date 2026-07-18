#if os(macOS)

    import Foundation
    import Testing
    import Combine

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

            // The current local-ASR baseline uses SenseVoice for every language selection.
            #expect(viewModel.transcriptionPrimaryLanguage == "en")
            #expect(viewModel.transcriptionEngine == .sherpaOnnxSenseVoice)

            viewModel.transcriptionPrimaryLanguage = "is"
            #expect(viewModel.transcriptionEngine == .sherpaOnnxSenseVoice)

            viewModel.transcriptionSecondaryLanguage = "zh-Hans"
            #expect(viewModel.transcriptionEngine == .sherpaOnnxSenseVoice)

            viewModel.transcriptionPrimaryLanguage = "en"
            #expect(viewModel.transcriptionEngine == .sherpaOnnxSenseVoice)
        }

        @Test func testEnginePreparationFlow() async throws {
            let defaults = TestSupport.makeUserDefaults()
            let secretStore = TestSecretStore()
            let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: secretStore)
            let coordinator = MockOnboardingCoordinator(step: .language)

            // We'll use the real managers but they'll likely hit mockable paths or we check the state machine
            let viewModel = OnboardingViewModel(
                coordinator: coordinator,
                settingsStore: settingsStore
            )

            #expect(viewModel.engineDownloadState == .idle)

            // Start preparation
            await viewModel.handleEngineDownloadPrimaryAction()

            // Since we can't easily mock the internal downloaders without more refactoring,
            // we at least check that it's no longer idle or has reached a state.
            #expect(viewModel.engineDownloadState != .idle)
        }
    }

#endif
