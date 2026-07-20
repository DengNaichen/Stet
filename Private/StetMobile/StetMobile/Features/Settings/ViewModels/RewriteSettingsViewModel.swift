import Foundation
import Combine
import StetAI
import StetCore

@MainActor
final class RewriteSettingsViewModel: ObservableObject {
    var settingsStore: RewriteSettingsStore
    var dictationSettingsStore: MobileDictationSettingsStore
    var funASRSettingsStore: FunASRSettingsStore
    private let validationService: ProviderCredentialValidationService
    private let funASRConnectionValidator: any FunASRConnectionValidating
    private let localModelManagers: [MobileDictationEngine: any LocalDictationModelManaging]
    private let onLocalModelReady: @MainActor (MobileDictationEngine) -> Void
    private let dictationEngineSelectionHandler: @MainActor (MobileDictationEngine) -> Void

    @Published var apiKeyInput: String = ""
    @Published var funASRAPIKeyInput: String = ""
    @Published private(set) var validationState: ValidationState = .idle
    @Published private(set) var funASRValidationState: ValidationState = .idle
    @Published private var localModelStates: [MobileDictationEngine: LocalModelState] = [:]

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
        dictationSettingsStore: MobileDictationSettingsStore? = nil,
        funASRSettingsStore: FunASRSettingsStore? = nil,
        funASRConnectionValidator: (any FunASRConnectionValidating)? = nil,
        localModelManagers: [MobileDictationEngine: any LocalDictationModelManaging],
        onLocalModelReady: @escaping @MainActor (MobileDictationEngine) -> Void = { _ in },
        onDictationEngineSelected: @escaping @MainActor (MobileDictationEngine) -> Void = { _ in }
    ) {
        self.settingsStore = settingsStore
        self.dictationSettingsStore = dictationSettingsStore ?? MobileDictationSettingsStore()
        self.funASRSettingsStore = funASRSettingsStore ?? FunASRSettingsStore()
        self.validationService = ProviderCredentialValidationService()
        self.funASRConnectionValidator = funASRConnectionValidator ?? FunASRConnectionValidator()
        self.localModelManagers = localModelManagers
        self.onLocalModelReady = onLocalModelReady
        self.dictationEngineSelectionHandler = onDictationEngineSelected
        self.apiKeyInput = settingsStore.loadAPIKey(for: settingsStore.selectedProvider) ?? ""
        self.funASRAPIKeyInput = (try? self.funASRSettingsStore.loadAPIKey()) ?? ""
    }

    var availableDictationEngines: [MobileDictationEngine] {
        MobileDictationEngine.allCases
    }

    var availableLocalDictationEngines: [MobileDictationEngine] {
        MobileDictationEngine.localEngines
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

    func onDictationEngineSelected() {
        dictationEngineSelectionHandler(dictationSettingsStore.selectedEngine)
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

    func localModelState(for engine: MobileDictationEngine) -> LocalModelState {
        localModelStates[engine] ?? .checking
    }

    func refreshLocalModelStatuses() async {
        for engine in availableLocalDictationEngines {
            await refreshLocalModelStatus(for: engine)
        }
    }

    func refreshLocalModelStatus(for engine: MobileDictationEngine) async {
        guard engine.isLocal, let manager = localModelManagers[engine] else {
            localModelStates[engine] = .downloadFailed
            return
        }

        repeat {
            let status = await manager.status()
            localModelStates[engine] = Self.localModelState(for: status)

            guard case .downloading = status else { return }
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
        } while !Task.isCancelled
    }

    func downloadLocalModel(_ engine: MobileDictationEngine) async {
        guard engine.isLocal, let manager = localModelManagers[engine],
            localModelState(for: engine) != .downloading
        else {
            return
        }

        localModelStates[engine] = .downloading
        do {
            try await manager.download()
            localModelStates[engine] = .downloaded
            onLocalModelReady(engine)
        } catch is CancellationError {
            await refreshLocalModelStatus(for: engine)
        } catch {
            localModelStates[engine] = .downloadFailed
        }
    }

    func deleteLocalModel(_ engine: MobileDictationEngine) async {
        guard engine.isLocal, let manager = localModelManagers[engine],
            localModelState(for: engine) != .deleting
        else {
            return
        }

        localModelStates[engine] = .deleting
        do {
            try await manager.delete()
            localModelStates[engine] = .notDownloaded
        } catch is CancellationError {
            await refreshLocalModelStatus(for: engine)
        } catch {
            localModelStates[engine] = .deletionFailed
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
