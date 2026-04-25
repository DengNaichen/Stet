#if os(macOS)
    import AuthenticationServices
    import Combine
    import Foundation
    import KeyboardShortcuts

    @MainActor
    final class OnboardingViewModel: ObservableObject {
        enum LocalWhisperDownloadState: Equatable {
            case idle
            case running(LocalWhisperDownloadStage)
            case ready(modelPath: String)
            case failed(String)
        }

        @Published var apiKeyProvider: DictationProvider {
            didSet {
                if apiKeyProvider != lastValidatedProvider {
                    resetAPIKeyValidationState()
                }
            }
        }
        @Published var apiKey = "" {
            didSet {
                if apiKey != lastValidatedKey {
                    resetAPIKeyValidationState()
                }
            }
        }
        @Published private(set) var isValidatingAPIKey = false
        @Published private(set) var isAPIKeyValidated = false
        @Published private(set) var apiKeyStatusMessage: String?
        @Published private(set) var apiKeyErrorMessage: String?
        @Published private(set) var shortcutSummaryText = "Shortcut configured"
        @Published private(set) var onboardingPreviewTheme: MacDictationVisualTheme = .egg
        @Published private(set) var localWhisperDownloadState: LocalWhisperDownloadState = .idle
        @Published private(set) var localWhisperDownloadFraction: Double = 0
        @Published private(set) var localWhisperBytesCompleted: Int64 = 0
        @Published private(set) var localWhisperBytesTotal: Int64 = 0

        private let coordinator: any MacPermissionsCoordinating
        private let settingsStore: DictationSettingsStore
        private let credentialValidationService: any ProviderCredentialValidating
        private let localWhisperModelManager: LocalWhisperModelManager
        private var cancellables = Set<AnyCancellable>()
        private var lastValidatedKey: String?
        private var lastValidatedProvider: DictationProvider?

        init(
            coordinator: any MacPermissionsCoordinating,
            settingsStore: DictationSettingsStore = DictationSettingsStore(),
            credentialValidationService: (any ProviderCredentialValidating)? = nil,
            localWhisperModelManager: LocalWhisperModelManager = LocalWhisperModelManager()
        ) {
            self.coordinator = coordinator
            self.settingsStore = settingsStore
            self.credentialValidationService = credentialValidationService ?? ProviderCredentialValidationService()
            self.localWhisperModelManager = localWhisperModelManager
            let storedAPIKeyProvider = settingsStore.loadProvider()
            self.apiKeyProvider = storedAPIKeyProvider.requiresAPIKey ? storedAPIKeyProvider : .openAI
            coordinator.updates
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }

        var autoPasteStatusText: String {
            coordinator.autoPasteStatusText
        }

        var microphoneAccessStatusText: String {
            coordinator.microphoneAccessStatusText
        }

        var microphoneAccessNeedsAttention: Bool {
            coordinator.microphoneAccessNeedsAttention
        }

        var microphonePermissionActionTitle: String {
            coordinator.microphonePermissionActionTitle
        }

        var autoPasteAccessNeedsAttention: Bool {
            coordinator.autoPasteAccessNeedsAttention
        }

        var hasRequiredPermissions: Bool {
            !microphoneAccessNeedsAttention && !autoPasteAccessNeedsAttention
        }

        var onboardingStep: MacOnboardingStep {
            coordinator.onboardingStep
        }

        var onboardingMode: MacOnboardingMode? {
            coordinator.onboardingMode
        }

        var shortcutTestDetectedPress: Bool {
            coordinator.shortcutTestDetectedPress
        }

        var shortcutTestCompletedRoundTrip: Bool {
            coordinator.shortcutTestCompletedRoundTrip
        }

        var shortcutTestPreviewText: String? {
            coordinator.shortcutTestPreviewText
        }

        var canContinueShortcutOnboarding: Bool {
            coordinator.canContinueShortcutOnboarding
        }

        var firstSuccessPreviewText: String? {
            coordinator.firstSuccessPreviewText
        }

        var firstSuccessFailureMessage: String? {
            coordinator.firstSuccessFailureMessage
        }

        var canContinueFirstSuccessOnboarding: Bool {
            coordinator.canContinueFirstSuccessOnboarding
        }

        var canSkipFirstSuccessOnboarding: Bool {
            coordinator.canSkipFirstSuccessOnboarding
        }

        var canFinishAppearanceOnboarding: Bool {
            coordinator.canFinishAppearanceOnboarding
        }

        var localWhisperDownloadPrimaryButtonTitle: String {
            switch localWhisperDownloadState {
            case .idle:
                return "Download"
            case .running(let stage):
                switch stage {
                case .checkingExistingAssets:
                    return "Checking..."
                case .downloadingModel:
                    return "Downloading..."
                case .ready:
                    return "Continue"
                }
            case .ready(_):
                return "Continue"
            case .failed(_):
                return "Try again"
            }
        }

        var isLocalWhisperDownloadRunning: Bool {
            if case .running(let stage) = localWhisperDownloadState {
                return stage != .ready
            }
            return false
        }

        var isLocalWhisperDownloadFailed: Bool {
            if case .failed = localWhisperDownloadState {
                return true
            }
            return false
        }

        var localWhisperDownloadDetailText: String {
            switch localWhisperDownloadState {
            case .idle:
                return "One click gets you ready."
            case .running(let stage):
                switch stage {
                case .checkingExistingAssets:
                    return "Working..."
                case .downloadingModel:
                    return "Downloading..."
                case .ready:
                    return "You're set."
                }
            case .ready(_):
                return "You're set."
            case .failed(let message):
                return message
            }
        }

        var localWhisperDownloadProgress: Double {
            switch localWhisperDownloadState {
            case .idle:
                return 0.0
            case .running(let stage):
                switch stage {
                case .checkingExistingAssets:
                    return 0.04
                case .downloadingModel:
                    return localWhisperDownloadFraction
                case .ready:
                    return 1.0
                }
            case .ready(_):
                return 1.0
            case .failed(_):
                return 0.0
            }
        }

        var localWhisperDownloadProgressLabel: String {
            switch localWhisperDownloadState {
            case .idle:
                return "Ready to download"
            case .running(let stage):
                switch stage {
                case .checkingExistingAssets:
                    return "Preparing"
                case .downloadingModel:
                    let percentage = Int((localWhisperDownloadFraction * 100).rounded())
                    let completedMB = Double(localWhisperBytesCompleted) / 1_048_576.0
                    let totalMB = Double(localWhisperBytesTotal) / 1_048_576.0

                    if localWhisperBytesTotal > 0 {
                        return String(format: "Downloading %d%% (%.1f MB / %.1f MB)", percentage, completedMB, totalMB)
                    } else if localWhisperBytesCompleted > 0 {
                        return String(format: "Downloading (%.1f MB)", completedMB)
                    } else {
                        return percentage > 0 ? "Downloading \(percentage)%" : "Downloading"
                    }
                case .ready:
                    return "Done"
                }
            case .ready(_):
                return "Done"
            case .failed(_):
                return "Try again"
            }
        }

        var localWhisperDownloadStatusTitle: String {
            switch localWhisperDownloadState {
            case .idle:
                return "Get ready"
            case .running(let stage):
                switch stage {
                case .checkingExistingAssets:
                    return "Preparing"
                case .ready:
                    return "Ready"
                default:
                    return "Downloading"
                }
            case .ready(_):
                return "Ready"
            case .failed(_):
                return "Failed"
            }
        }

        var localWhisperExpectedModelPath: String {
            (try? localWhisperModelManager.defaultModelURL().path)
                ?? "Unable to resolve Local Whisper model path."
        }

        var canContinueLocalWhisperDownload: Bool {
            switch localWhisperDownloadState {
            case .ready:
                return true
            case .running(let stage):
                return stage == .ready
            default:
                return false
            }
        }

        var apiKeyPrimaryButtonTitle: String {
            if isAPIKeyValidated || !apiKeyProvider.requiresAPIKey {
                return "Continue"
            }

            return isValidatingAPIKey ? "Validating..." : "Verify Key"
        }

        func requestAutoPasteAccess() {
            coordinator.requestAutoPasteAccess()
        }

        func resolveMicrophoneAccess() {
            coordinator.resolveMicrophoneAccess()
        }

        func openAccessibilitySettings() {
            coordinator.openAccessibilitySettings()
        }

        func chooseOnboardingMode(_ mode: MacOnboardingMode) {
            clearFlowMessages()
            coordinator.chooseOnboardingMode(mode)
        }

        func prepareLocalWhisperModelIfNeeded() async {
            if case .ready = localWhisperDownloadState {
                return
            }

            if case .running = localWhisperDownloadState {
                return
            }

            do {
                localWhisperDownloadFraction = 0
                if try localWhisperModelManager.defaultModelReady() {
                    try localWhisperModelManager.removeDefaultEncoderIfPresent()
                    LocalWhisperModelManager.saveCustomModelPath(nil)
                    localWhisperDownloadFraction = 1
                    localWhisperDownloadState = .ready(modelPath: try localWhisperModelManager.defaultModelURL().path)
                    return
                }

                localWhisperDownloadState = .running(.checkingExistingAssets)
                try await localWhisperModelManager.installDefaultModel(
                    progress: { [weak self] stage in
                        Task { @MainActor [weak self, stage] in
                            self?.localWhisperDownloadState = .running(stage)
                        }
                    },
                    downloadProgress: { [weak self] fraction, completed, total in
                        Task { @MainActor [weak self, fraction, completed, total] in
                            self?.localWhisperDownloadFraction = fraction
                            self?.localWhisperBytesCompleted = completed
                            self?.localWhisperBytesTotal = total
                        }
                    }
                )

                LocalWhisperModelManager.saveCustomModelPath(nil)
                localWhisperDownloadFraction = 1
                localWhisperDownloadState = .ready(modelPath: try localWhisperModelManager.defaultModelURL().path)

                // Trigger proactive high-priority background warm-up.
                // This shouldn't block the user from moving to the next onboarding steps.
                Task.detached(priority: .userInitiated) { [localWhisperModelManager] in
                    try? await localWhisperModelManager.installDefaultAssets()
                    try? await LocalWhisperWarmupCoordinator.shared.warmup()
                }
            } catch {
                localWhisperDownloadFraction = 0
                localWhisperDownloadState = .failed(error.localizedDescription)
            }
        }

        func handleLocalWhisperDownloadPrimaryAction() async {
            if canContinueLocalWhisperDownload {
                continueOnboarding()
                return
            }

            switch localWhisperDownloadState {
            case .idle, .failed:
                await prepareLocalWhisperModelIfNeeded()
            default:
                break
            }
        }

        func selectOnboardingAppearanceTheme(_ theme: MacDictationVisualTheme) {
            onboardingPreviewTheme = theme
            coordinator.selectOnboardingAppearanceTheme(theme)
        }

        func applyOnboardingAppearanceTheme() {
            coordinator.applyOnboardingAppearanceTheme()
        }

        func continueOnboarding() {
            coordinator.advanceOnboarding()
        }

        func retreatOnboarding() {
            clearFlowMessages()
            coordinator.retreatOnboarding()
        }

        func completeAPIKeyFlow() async {
            if isAPIKeyValidated || !apiKeyProvider.requiresAPIKey {
                coordinator.completeAPIKeyOnboarding(provider: apiKeyProvider)
                return
            }

            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else {
                apiKeyErrorMessage = "Please enter API Key."
                apiKeyStatusMessage = nil
                return
            }

            isValidatingAPIKey = true
            apiKeyErrorMessage = nil
            apiKeyStatusMessage = nil

            do {
                try await credentialValidationService.validateCredential(
                    apiKey: trimmedKey,
                    provider: apiKeyProvider
                )
                try settingsStore.saveAPIKey(trimmedKey, for: apiKeyProvider)
                apiKey = trimmedKey
                lastValidatedKey = trimmedKey
                lastValidatedProvider = apiKeyProvider
                isAPIKeyValidated = true
                apiKeyStatusMessage = "API Key verified."
            } catch {
                apiKeyErrorMessage = mapAPIKeyError(error)
            }

            isValidatingAPIKey = false
        }

        func finishOnboarding() {
            coordinator.finishOnboarding()
        }

        func updateShortcutSummary(_ shortcut: KeyboardShortcuts.Shortcut?) {
            shortcutSummaryText = shortcut.map { "\($0)" } ?? "Shortcut configured"
        }

        private func clearFlowMessages() {
            apiKeyStatusMessage = nil
            apiKeyErrorMessage = nil
        }

        private func resetAPIKeyValidationState() {
            isAPIKeyValidated = false
            apiKeyStatusMessage = nil
            apiKeyErrorMessage = nil
            lastValidatedKey = nil
            lastValidatedProvider = nil
        }

        private func mapAPIKeyError(_ error: Error) -> String {
            if let openAIError = error as? OpenAIError {
                switch openAIError {
                case .missingAPIKey:
                    return "Invalid Key format."
                case .api(_, let statusCode, _):
                    switch statusCode {
                    case 401, 403:
                        return "Verification failed, please check if it was copied completely."
                    case 429, 500, 502, 503, 504:
                        return "Provider is temporarily unavailable."
                    default:
                        return openAIError.localizedDescription
                    }
                case .invalidBaseURL, .invalidResponse:
                    return "Provider is temporarily unavailable."
                case .fileNotFound, .missingTranscriptionText, .missingRewriteText:
                    return openAIError.localizedDescription
                }
            }

            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                    return "Network connection error."
                default:
                    return urlError.localizedDescription
                }
            }

            return error.localizedDescription
        }
    }
#endif
