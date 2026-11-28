import Combine
import Foundation
import StetAI
import StetCore

@MainActor
final class RewriteSettingsViewModel: ObservableObject {
    var settingsStore: RewriteSettingsStore
    var speechSettingsStore: SpeechRecognitionSettingsStore
    private let validationService: any ProviderCredentialValidating
    private let modelProbe: any OpenAICompatibleModelProbing
    private var cancellables: Set<AnyCancellable> = []
    private var lastLoadedProvider: DictationProvider
    private var lastLoadedAPIKey: String

    @Published var apiKeyInput: String = ""
    @Published private(set) var validationState: ValidationState = .idle

    var onSpeechAssetBecameReady: (() -> Void)?
    var onMicrophoneKeepAliveChanged: ((MicrophoneKeepAliveDuration) -> Void)?

    enum ValidationState: Equatable {
        case idle
        case validating
        case success
        case failed(String)
    }

    init(
        settingsStore: RewriteSettingsStore,
        speechSettingsStore: SpeechRecognitionSettingsStore? = nil,
        validationService: any ProviderCredentialValidating = ProviderCredentialValidationService(),
        modelProbe: (any OpenAICompatibleModelProbing)? = nil
    ) {
        self.settingsStore = settingsStore
        let resolvedSpeechStore = speechSettingsStore ?? SpeechRecognitionSettingsStore()
        self.speechSettingsStore = resolvedSpeechStore
        self.validationService = validationService
        self.modelProbe = modelProbe ?? OpenAICompatibleModelProbe()
        let initialProvider = settingsStore.selectedProvider
        let initialKey = settingsStore.loadAPIKey(for: initialProvider) ?? ""
        self.lastLoadedProvider = initialProvider
        self.lastLoadedAPIKey = initialKey
        self.apiKeyInput = initialKey

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

    var microphoneKeepAliveDuration: MicrophoneKeepAliveDuration {
        get { speechSettingsStore.microphoneKeepAliveDuration }
        set {
            guard speechSettingsStore.microphoneKeepAliveDuration != newValue else { return }
            speechSettingsStore.microphoneKeepAliveDuration = newValue
            onMicrophoneKeepAliveChanged?(newValue)
        }
    }

    var rewriteSummary: String {
        guard settingsStore.isRewriteEnabled else { return "Off" }
        if settingsStore.selectedProvider == .custom {
            let trimmed = settingsStore.customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? settingsStore.selectedProvider.displayName : trimmed
        }
        return settingsStore.selectedModel.displayName
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

    func refreshSyncedAPIKey() {
        let provider = settingsStore.selectedProvider
        let syncedKey = settingsStore.loadAPIKey(for: provider) ?? ""
        let hasUnsavedEdits = provider == lastLoadedProvider && apiKeyInput != lastLoadedAPIKey
        guard !hasUnsavedEdits else { return }
        lastLoadedProvider = provider
        lastLoadedAPIKey = syncedKey
        if apiKeyInput != syncedKey {
            apiKeyInput = syncedKey
        }
    }

    func onProviderChanged() {
        let provider = settingsStore.selectedProvider
        let loadedKey = settingsStore.loadAPIKey(for: provider) ?? ""
        lastLoadedProvider = provider
        lastLoadedAPIKey = loadedKey
        apiKeyInput = loadedKey
        settingsStore.selectedModel = RewriteModel.default(for: provider)
        validationState = .idle
    }

    func saveAPIKey() {
        do {
            try persistCurrentAPIKey(for: settingsStore.selectedProvider)
            if case .failed = validationState {
                validationState = .idle
            }
        } catch {
            validationState = .failed(keychainSaveErrorMessage(for: error))
        }
    }

    func validateCredential() async {
        if settingsStore.selectedProvider == .custom {
            await validateCustomEndpoint()
            return
        }

        let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            validationState = .failed("Enter an API key first.")
            return
        }
        validationState = .validating
        let provider = settingsStore.selectedProvider
        do {
            try await validationService.validateCredential(
                apiKey: trimmedKey,
                provider: provider
            )
        } catch {
            validationState = .failed("The API key couldn't be validated. Check it and try again.")
            return
        }

        do {
            try persistCurrentAPIKey(for: provider)
            validationState = .success
        } catch {
            validationState = .failed(keychainSaveErrorMessage(for: error))
        }
    }

    private func validateCustomEndpoint() async {
        validationState = .validating
        let models: [String]
        do {
            let url = try OpenAICompatibleBaseURL.normalize(settingsStore.customBaseURL)
            models = try await modelProbe.listModels(baseURL: url, apiKey: apiKeyInput)
        } catch {
            validationState = .failed(error.localizedDescription)
            return
        }

        settingsStore.discoveredCustomModels = models
        if settingsStore.customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let first = models.first
        {
            settingsStore.customModelID = first
        }

        do {
            try persistCurrentAPIKey(for: .custom)
            validationState = .success
        } catch {
            validationState = .failed(keychainSaveErrorMessage(for: error))
        }
    }

    private func persistCurrentAPIKey(for provider: DictationProvider) throws {
        try settingsStore.saveAPIKey(apiKeyInput, for: provider)
        let normalizedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKeyInput = normalizedKey
        lastLoadedProvider = provider
        lastLoadedAPIKey = normalizedKey
    }

    private func keychainSaveErrorMessage(for error: Error) -> String {
        let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return "Could not save the API key to Keychain."
        }
        return "Could not save the API key to Keychain: \(detail)"
    }
}
