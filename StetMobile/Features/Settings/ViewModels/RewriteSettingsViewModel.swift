import Foundation
import Combine
import StetAI
import StetCore

@MainActor
final class RewriteSettingsViewModel: ObservableObject {
    var settingsStore: RewriteSettingsStore
    private let validationService: ProviderCredentialValidationService
    private let localModelManager: any LocalDictationModelManaging
    private let onLocalModelReady: @MainActor () -> Void

    @Published var apiKeyInput: String = ""
    @Published private(set) var validationState: ValidationState = .idle
    @Published private(set) var localModelState: LocalModelState = .checking

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
        localModelManager: any LocalDictationModelManaging,
        onLocalModelReady: @escaping @MainActor () -> Void = {}
    ) {
        self.settingsStore = settingsStore
        self.validationService = ProviderCredentialValidationService()
        self.localModelManager = localModelManager
        self.onLocalModelReady = onLocalModelReady
        self.apiKeyInput = settingsStore.loadAPIKey(for: settingsStore.selectedProvider) ?? ""
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

    func refreshLocalModelStatus() async {
        repeat {
            let status = await localModelManager.status()
            localModelState = Self.localModelState(for: status)

            guard case .downloading = status else { return }
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
        } while !Task.isCancelled
    }

    func downloadLocalModel() async {
        guard localModelState != .downloading else { return }

        localModelState = .downloading
        do {
            try await localModelManager.download()
            localModelState = .downloaded
            onLocalModelReady()
        } catch is CancellationError {
            await refreshLocalModelStatus()
        } catch {
            localModelState = .downloadFailed
        }
    }

    func deleteLocalModel() async {
        guard localModelState != .deleting else { return }

        localModelState = .deleting
        do {
            try await localModelManager.delete()
            localModelState = .notDownloaded
        } catch is CancellationError {
            await refreshLocalModelStatus()
        } catch {
            localModelState = .deletionFailed
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
