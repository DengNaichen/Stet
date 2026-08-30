import Foundation
import Combine
import StetAI
import StetCore

@MainActor
final class RewriteSettingsViewModel: ObservableObject {
    var settingsStore: RewriteSettingsStore
    var funASRSettingsStore: FunASRSettingsStore
    private let validationService: ProviderCredentialValidationService
    private let funASRConnectionValidator: any FunASRConnectionValidating

    @Published var apiKeyInput: String = ""
    @Published var funASRAPIKeyInput: String = ""
    @Published private(set) var validationState: ValidationState = .idle
    @Published private(set) var funASRValidationState: ValidationState = .idle

    enum ValidationState: Equatable {
        case idle
        case validating
        case success
        case failed(String)
    }

    init(
        settingsStore: RewriteSettingsStore,
        funASRSettingsStore: FunASRSettingsStore? = nil,
        funASRConnectionValidator: (any FunASRConnectionValidating)? = nil
    ) {
        self.settingsStore = settingsStore
        self.funASRSettingsStore = funASRSettingsStore ?? FunASRSettingsStore()
        self.validationService = ProviderCredentialValidationService()
        self.funASRConnectionValidator = funASRConnectionValidator ?? FunASRConnectionValidator()
        self.apiKeyInput = settingsStore.loadAPIKey(for: settingsStore.selectedProvider) ?? ""
        self.funASRAPIKeyInput = (try? self.funASRSettingsStore.loadAPIKey()) ?? ""
    }

    var availableProviders: [DictationProvider] {
        DictationProvider.allCases.filter { $0 != .appleIntelligence }
    }

    func onProviderChanged() {
        apiKeyInput = settingsStore.loadAPIKey(for: settingsStore.selectedProvider) ?? ""
        settingsStore.selectedModel = RewriteModel.default(for: settingsStore.selectedProvider)
        validationState = .idle
    }

    func saveAPIKey() {
        settingsStore.saveAPIKey(apiKeyInput, for: settingsStore.selectedProvider)
    }

    func validateCredential() async {
        guard !apiKeyInput.isEmpty else {
            validationState = .failed("Enter an API key first.")
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
            validationState = .failed("The API key couldn't be validated. Check it and try again.")
        }
    }

    func saveFunASRAPIKey() {
        do {
            try funASRSettingsStore.saveAPIKey(funASRAPIKeyInput)
            funASRValidationState = .idle
        } catch {
            funASRValidationState = .failed("The FunASR API key could not be saved securely.")
        }
    }

    func sanitizeFunASRWorkspaceID() {
        let sanitized = String(
            funASRSettingsStore.workspaceID.filter { character in
                character.unicodeScalars.count == 1
                    && character.unicodeScalars.allSatisfy {
                        (65...90).contains($0.value)
                            || (97...122).contains($0.value)
                            || (48...57).contains($0.value)
                            || $0.value == 45
                    }
            })
        if sanitized != funASRSettingsStore.workspaceID {
            funASRSettingsStore.workspaceID = sanitized
        }
        funASRValidationState = .idle
    }

    func validateFunASRConnection() async {
        funASRValidationState = .validating
        do {
            let configuration = try funASRSettingsStore.configuration(apiKey: funASRAPIKeyInput)
            try await funASRConnectionValidator.validate(configuration: configuration)
            try funASRSettingsStore.saveAPIKey(funASRAPIKeyInput)
            funASRValidationState = .success
        } catch let error as FunASRConfigurationError {
            funASRValidationState = .failed(error.localizedDescription)
        } catch let error as FunASRError {
            funASRValidationState = .failed(error.localizedDescription)
        } catch {
            funASRValidationState = .failed(
                "The FunASR connection could not be validated. Check the credentials and try again."
            )
        }
    }

}
