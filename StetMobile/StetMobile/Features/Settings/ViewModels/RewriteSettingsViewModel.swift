import Combine
import Foundation
import StetAI
import StetCore

@MainActor
final class RewriteSettingsViewModel: ObservableObject {
    var settingsStore: RewriteSettingsStore
    var speechSettingsStore: SpeechRecognitionSettingsStore
    private let validationService: ProviderCredentialValidationService
    private let modelProbe: any OpenAICompatibleModelProbing
    private var cancellables: Set<AnyCancellable> = []

    @Published var apiKeyInput: String = ""
    @Published private(set) var validationState: ValidationState = .idle

    var onSpeechAssetBecameReady: (() -> Void)?

    enum ValidationState: Equatable {
        case idle
        case validating
        case success
        case failed(String)
    }

    init(
        settingsStore: RewriteSettingsStore,
        speechSettingsStore: SpeechRecognitionSettingsStore? = nil,
        modelProbe: (any OpenAICompatibleModelProbing)? = nil
    ) {
        self.settingsStore = settingsStore
        let resolvedSpeechStore = speechSettingsStore ?? SpeechRecognitionSettingsStore()
        self.speechSettingsStore = resolvedSpeechStore
        self.validationService = ProviderCredentialValidationService()
        self.modelProbe = modelProbe ?? OpenAICompatibleModelProbe()
        self.apiKeyInput = settingsStore.loadAPIKey(for: settingsStore.selectedProvider) ?? ""

        settingsStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        resolvedSpeechStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var availableProviders: [DictationProvider] {
        DictationProvider.allCases.filter {
            $0 != .appleIntelligence && $0 != .groq && $0 != .doubao && $0 != .anthropic
        }
    }

    var selectedLanguage: SpeechRecognitionLanguage {
        get { speechSettingsStore.selectedLanguage }
        set {
            guard speechSettingsStore.selectedLanguage != newValue else { return }
            speechSettingsStore.selectedLanguage = newValue
            Task { await refreshSpeechAssetStatus() }
        }
    }

    var selectedBackend: SpeechTranscriberBackend {
        get { speechSettingsStore.selectedBackend }
        set {
            guard speechSettingsStore.selectedBackend != newValue else { return }
            speechSettingsStore.selectedBackend = newValue
            Task { await refreshSpeechAssetStatus() }
        }
    }

    var speechAssetStatus: SpeechAssetStatus {
        speechSettingsStore.assetStatus
    }

    func refreshSpeechAssetStatus() async {
        await speechSettingsStore.refreshAssetStatus()
    }

    func downloadSpeechAsset() async {
        do {
            try await speechSettingsStore.downloadAssetIfNeeded()
            if speechSettingsStore.assetStatus.isReady {
                onSpeechAssetBecameReady?()
            }
        } catch {
            await speechSettingsStore.refreshAssetStatus()
        }
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
        if settingsStore.selectedProvider == .custom {
            await validateCustomEndpoint()
            return
        }

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

    private func validateCustomEndpoint() async {
        validationState = .validating
        do {
            let url = try OpenAICompatibleBaseURL.normalize(settingsStore.customBaseURL)
            let models = try await modelProbe.listModels(baseURL: url, apiKey: apiKeyInput)
            settingsStore.discoveredCustomModels = models
            settingsStore.saveAPIKey(apiKeyInput, for: .custom)
            if settingsStore.customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let first = models.first
            {
                settingsStore.customModelID = first
            }
            validationState = .success
        } catch {
            validationState = .failed(error.localizedDescription)
        }
    }
}
