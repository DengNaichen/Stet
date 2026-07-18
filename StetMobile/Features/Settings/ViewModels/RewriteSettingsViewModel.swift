import Foundation
import Combine
import StetAI
import StetCore

@MainActor
final class RewriteSettingsViewModel: ObservableObject {
    var settingsStore: RewriteSettingsStore
    var dictationSettingsStore: LocalDictationSettingsStore
    private let validationService: ProviderCredentialValidationService
    private let localModelManagers: [MobileDictationModel: any LocalDictationModelManaging]
    private let onLocalModelReady: @MainActor (MobileDictationModel) -> Void
    private let onLocalModelSelected: @MainActor (MobileDictationModel) -> Void

    @Published var apiKeyInput: String = ""
    @Published private(set) var validationState: ValidationState = .idle
    @Published private var localModelStates: [MobileDictationModel: LocalModelState] = [:]

    enum ValidationState: Equatable {
        case idle
        case validating
        case success
        case failed(String)
    }

    enum LocalModelState: Equatable {
        case checking
        case notDownloaded
        case downloading
        case downloaded
        case deleting
        case downloadFailed
        case deletionFailed
    }

    init(
        settingsStore: RewriteSettingsStore,
        dictationSettingsStore: LocalDictationSettingsStore? = nil,
        localModelManagers: [MobileDictationModel: any LocalDictationModelManaging],
        onLocalModelReady: @escaping @MainActor (MobileDictationModel) -> Void = { _ in },
        onLocalModelSelected: @escaping @MainActor (MobileDictationModel) -> Void = { _ in }
    ) {
        self.settingsStore = settingsStore
        self.dictationSettingsStore = dictationSettingsStore ?? LocalDictationSettingsStore()
        self.validationService = ProviderCredentialValidationService()
        self.localModelManagers = localModelManagers
        self.onLocalModelReady = onLocalModelReady
        self.onLocalModelSelected = onLocalModelSelected
        self.apiKeyInput = settingsStore.loadAPIKey(for: settingsStore.selectedProvider) ?? ""
    }

    var availableDictationModels: [MobileDictationModel] {
        MobileDictationModel.allCases
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

    func onDictationModelSelected() {
        onLocalModelSelected(dictationSettingsStore.selectedModel)
    }

    func localModelState(for model: MobileDictationModel) -> LocalModelState {
        localModelStates[model] ?? .checking
    }

    func refreshLocalModelStatuses() async {
        for model in availableDictationModels {
            await refreshLocalModelStatus(for: model)
        }
    }

    func refreshLocalModelStatus(for model: MobileDictationModel) async {
        guard let manager = localModelManagers[model] else {
            localModelStates[model] = .downloadFailed
            return
        }

        repeat {
            let status = await manager.status()
            localModelStates[model] = Self.localModelState(for: status)

            guard case .downloading = status else { return }
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
        } while !Task.isCancelled
    }

    func downloadLocalModel(_ model: MobileDictationModel) async {
        guard let manager = localModelManagers[model], localModelState(for: model) != .downloading else {
            return
        }

        localModelStates[model] = .downloading
        do {
            try await manager.download()
            localModelStates[model] = .downloaded
            onLocalModelReady(model)
        } catch is CancellationError {
            await refreshLocalModelStatus(for: model)
        } catch {
            localModelStates[model] = .downloadFailed
        }
    }

    func deleteLocalModel(_ model: MobileDictationModel) async {
        guard let manager = localModelManagers[model], localModelState(for: model) != .deleting else {
            return
        }

        localModelStates[model] = .deleting
        do {
            try await manager.delete()
            localModelStates[model] = .notDownloaded
        } catch is CancellationError {
            await refreshLocalModelStatus(for: model)
        } catch {
            localModelStates[model] = .deletionFailed
        }
    }

    private static func localModelState(for status: ASRModelStatus) -> LocalModelState {
        switch status {
        case .notDownloaded:
            .notDownloaded
        case .downloading:
            .downloading
        case .ready:
            .downloaded
        case .error:
            .downloadFailed
        }
    }
}
