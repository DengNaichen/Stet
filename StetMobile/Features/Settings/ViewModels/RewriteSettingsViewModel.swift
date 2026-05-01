import Foundation
import Combine
import StetAI
import StetCore

@MainActor
final class RewriteSettingsViewModel: ObservableObject {
    var settingsStore: RewriteSettingsStore
    private let validationService: ProviderCredentialValidationService

    @Published var apiKeyInput: String = ""
    @Published private(set) var validationState: ValidationState = .idle

    enum ValidationState: Equatable {
        case idle
        case validating
        case success
        case failed(String)
    }

    init(settingsStore: RewriteSettingsStore) {
        self.settingsStore = settingsStore
        self.validationService = ProviderCredentialValidationService()
        self.apiKeyInput = settingsStore.loadAPIKey(for: settingsStore.selectedProvider) ?? ""
    }

    var availableProviders: [DictationProvider] {
        DictationProvider.allCases.filter { $0 != .appleIntelligence }
    }

    func onProviderChanged() {
        apiKeyInput = settingsStore.loadAPIKey(for: settingsStore.selectedProvider) ?? ""
        settingsStore.selectedModel = DictationProviderDefaults.rewriteModel(for: settingsStore.selectedProvider)
        validationState = .idle
    }

    func saveAPIKey() {
        settingsStore.saveAPIKey(apiKeyInput, for: settingsStore.selectedProvider)
    }

    func validateCredential() async {
        guard !apiKeyInput.isEmpty else {
            validationState = .failed("API key is empty")
            return
        }
        validationState = .validating
        do {
            try await validationService.validateCredential(
                apiKey: apiKeyInput,
                provider: settingsStore.selectedProvider
            )
            settingsStore.saveAPIKey(apiKeyInput, for: settingsStore.selectedProvider)
            validationState = .success
        } catch {
            validationState = .failed(error.localizedDescription)
        }
    }
}
