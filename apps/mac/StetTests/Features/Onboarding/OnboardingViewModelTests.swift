#if os(macOS)
    internal import Auth
    import Foundation
    import Testing

    @testable import Stet

    @MainActor
    @Suite("Onboarding View Model", .serialized)
    struct OnboardingViewModelTests {
        @Test func completeAPIKeyFlowValidatesAndSavesProviderKey() async throws {
            let defaults = TestSupport.makeUserDefaults()
            let secretStore = TestSecretStore()
            let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: secretStore)
            let coordinator = MockOnboardingCoordinator(step: .apiKey)
            let validator = TestProviderCredentialValidator()
            let viewModel = OnboardingViewModel(
                coordinator: coordinator,
                settingsStore: settingsStore,
                supabase: TestOnboardingSupabaseAuthenticator(),
                credentialValidationService: validator
            )

            viewModel.apiKeyProvider = .openAI
            viewModel.apiKey = "  sk-live  "

            await viewModel.completeAPIKeyFlow()

            let calls = await validator.calls
            #expect(calls.count == 1)
            #expect(calls.first?.0 == .openAI)
            #expect(calls.first?.1 == "sk-live")
            #expect(viewModel.isAPIKeyValidated)
            #expect(viewModel.apiKeyStatusMessage == "API Key verified.")
            #expect(settingsStore.loadAPIKey(for: .openAI) == "sk-live")
            #expect(coordinator.mockStep == .apiKey)
        }

        @Test func completeAPIKeyFlowSurfacesValidationErrorWithoutSaving() async {
            let defaults = TestSupport.makeUserDefaults()
            let secretStore = TestSecretStore()
            let settingsStore = DictationSettingsStore(defaults: defaults, secretStore: secretStore)
            let validator = TestProviderCredentialValidator(
                error: OpenAIError.api(provider: .openAI, statusCode: 401, message: "bad key")
            )
            let viewModel = OnboardingViewModel(
                coordinator: MockOnboardingCoordinator(step: .apiKey),
                settingsStore: settingsStore,
                supabase: TestOnboardingSupabaseAuthenticator(),
                credentialValidationService: validator
            )

            viewModel.apiKeyProvider = .openAI
            viewModel.apiKey = "sk-bad"

            await viewModel.completeAPIKeyFlow()

            #expect(!viewModel.isAPIKeyValidated)
            #expect(
                viewModel.apiKeyErrorMessage == "Verification failed, please check if it was copied completely.")
            #expect(settingsStore.loadAPIKey(for: .openAI).isEmpty)
        }
    }

    actor TestProviderCredentialValidator: ProviderCredentialValidating {
        private(set) var calls: [(DictationProvider, String)] = []
        private let error: (any Error)?

        init(error: (any Error)? = nil) {
            self.error = error
        }

        func validateCredential(apiKey: String, provider: DictationProvider) async throws {
            calls.append((provider, apiKey))
            if let error {
                throw error
            }
        }
    }

    @MainActor
    final class TestOnboardingSupabaseAuthenticator: OnboardingSupabaseAuthenticating {
        var hasCurrentSession: Bool = false

        func signIn(email _: String, password _: String) async throws {}

        func signIn(provider _: Provider) async throws {}
    }
#endif
