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

            // The three-model router selects the engine from the active language combination.
            #expect(viewModel.transcriptionPrimaryLanguage == "en")
            #expect(viewModel.transcriptionEngine == .fluidAudio)

            viewModel.transcriptionPrimaryLanguage = "is"
            #expect(viewModel.transcriptionEngine == .localWhisper(languageHint: nil))

            viewModel.transcriptionSecondaryLanguage = "zh-Hans"
            #expect(viewModel.transcriptionEngine == .localWhisper(languageHint: nil))

            viewModel.transcriptionPrimaryLanguage = "en"
            #expect(viewModel.transcriptionEngine == .localWhisper(languageHint: nil))
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
