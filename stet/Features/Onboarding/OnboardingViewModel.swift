#if os(macOS)
    import AuthenticationServices
    import StetCore
    import Combine
    import FluidAudio
    import Foundation
    import KeyboardShortcuts

    @MainActor
    final class OnboardingViewModel: ObservableObject {
        enum EngineDownloadState: Equatable {
            case idle
            case running(stageText: String)
            case ready
            case failed(String)
        }

        @Published var transcriptionPrimaryLanguage: String = "en" {
            didSet {
                settingsStore.saveTranscriptionPrimaryLanguage(transcriptionPrimaryLanguage)
                updateEngineRouting()
            }
        }

        @Published var transcriptionSecondaryLanguage: String? = nil {
            didSet {
                settingsStore.saveTranscriptionSecondaryLanguage(transcriptionSecondaryLanguage)
                updateEngineRouting()
            }
        }

        @Published private(set) var transcriptionEngine: TranscriptionEngine = .localWhisper(languageHint: nil)

        @Published private(set) var shortcutSummaryText = "Shortcut configured"
        @Published private(set) var onboardingPreviewTheme: MacDictationVisualTheme = .egg
        @Published private(set) var engineDownloadState: EngineDownloadState = .idle
        @Published private(set) var engineDownloadFraction: Double = 0
        @Published private(set) var engineBytesCompleted: Int64 = 0
        @Published private(set) var engineBytesTotal: Int64 = 0

        private let coordinator: any MacPermissionsCoordinating
        private let settingsStore: DictationSettingsStore
        private let credentialValidationService: any ProviderCredentialValidating
        private let localWhisperModelManager: LocalWhisperModelManager
        private let fluidAudioModelManager: FluidAudioModelManager
        private let sherpaOnnxSenseVoiceModelManager: SherpaOnnxSenseVoiceModelManager
        private var cancellables = Set<AnyCancellable>()

        init(
            coordinator: any MacPermissionsCoordinating,
            settingsStore: DictationSettingsStore = DictationSettingsStore(),
            credentialValidationService: (any ProviderCredentialValidating)? = nil,
            localWhisperModelManager: LocalWhisperModelManager = LocalWhisperModelManager(),
            fluidAudioModelManager: FluidAudioModelManager = FluidAudioModelManager(),
            sherpaOnnxSenseVoiceModelManager: SherpaOnnxSenseVoiceModelManager = SherpaOnnxSenseVoiceModelManager()
        ) {
            self.coordinator = coordinator
            self.settingsStore = settingsStore
            self.credentialValidationService = credentialValidationService ?? ProviderCredentialValidationService()
            self.localWhisperModelManager = localWhisperModelManager
            self.fluidAudioModelManager = fluidAudioModelManager
            self.sherpaOnnxSenseVoiceModelManager = sherpaOnnxSenseVoiceModelManager

            self.transcriptionPrimaryLanguage = settingsStore.loadTranscriptionPrimaryLanguage()
            self.transcriptionSecondaryLanguage = settingsStore.loadTranscriptionSecondaryLanguage()
            self.transcriptionEngine = TranscriptionLanguageRouting.resolveEngine(
                primary: transcriptionPrimaryLanguage,
                secondary: transcriptionSecondaryLanguage
            )
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

        var engineDownloadPrimaryButtonTitle: String {
            switch engineDownloadState {
            case .idle:
                return "Download"
            case .running(let stage):
                if stage == "Ready" {
                    return "Continue"
                }
                return "Downloading..."
            case .ready:
                return "Continue"
            case .failed(_):
                return "Try again"
            }
        }

        var isEngineDownloadRunning: Bool {
            if case .running(let stage) = engineDownloadState {
                return stage != "Ready"
            }
            return false
        }

        var isEngineDownloadFailed: Bool {
            if case .failed = engineDownloadState {
                return true
            }
            return false
        }

        var engineDownloadDetailText: String {
            switch engineDownloadState {
            case .idle:
                return "One click gets you ready."
            case .running(let stage):
                return stage
            case .ready:
                return "You're set."
            case .failed(let message):
                return message
            }
        }

        var engineDownloadProgress: Double {
            switch engineDownloadState {
            case .idle:
                return 0.0
            case .running(_):
                return engineDownloadFraction
            case .ready:
                return 1.0
            case .failed(_):
                return 0.0
            }
        }

        var engineDownloadProgressLabel: String {
            switch engineDownloadState {
            case .idle:
                return "Ready to download"
            case .running(let stage):
                if stage == "Ready" {
                    return "Done"
                }
                let percentage = Int((engineDownloadFraction * 100).rounded())
                let completedMB = Double(engineBytesCompleted) / 1_048_576.0
                let totalMB = Double(engineBytesTotal) / 1_048_576.0

                if engineBytesTotal > 0 {
                    return String(format: "Downloading %d%% (%.1f MB / %.1f MB)", percentage, completedMB, totalMB)
                } else if engineBytesCompleted > 0 {
                    return String(format: "Downloading (%.1f MB)", completedMB)
                } else {
                    return percentage > 0 ? "Downloading \(percentage)%" : "Downloading"
                }
            case .ready:
                return "Done"
            case .failed(_):
                return "Try again"
            }
        }

        var engineDownloadStatusTitle: String {
            switch engineDownloadState {
            case .idle:
                return "Get ready"
            case .running(let stage):
                if stage == "Ready" {
                    return "Ready"
                }
                return "Downloading"
            case .ready:
                return "Ready"
            case .failed(_):
                return "Failed"
            }
        }

        var canContinueEngineDownload: Bool {
            switch engineDownloadState {
            case .ready:
                return true
            case .running(let stage):
                return stage == "Ready"
            default:
                return false
            }
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

        private func updateEngineRouting() {
            transcriptionEngine = TranscriptionLanguageRouting.resolveEngine(
                primary: transcriptionPrimaryLanguage,
                secondary: transcriptionSecondaryLanguage
            )
            // Reset download state when routing changes if we are still on the language step
            if coordinator.onboardingStep == .language {
                engineDownloadState = .idle
                engineDownloadFraction = 0
            }
        }

        func prepareTranscriptionEngineIfNeeded() async {
            if case .ready = engineDownloadState {
                return
            }

            if case .running = engineDownloadState {
                return
            }

            do {
                engineDownloadFraction = 0

                switch transcriptionEngine {
                case .fluidAudio:
                    if fluidAudioModelManager.isModelDownloaded() {
                        engineDownloadFraction = 1
                        engineDownloadState = .ready
                        settingsStore.saveTranscriptionEngine(.fluidAudio)
                        Task.detached(priority: .userInitiated) {
                            try? await LocalParakeetContextManager.shared.loadModel(version: .v3) { version in
                                try await AsrModels.loadFromCache(configuration: nil, version: version)
                            }
                        }
                        return
                    }

                    engineDownloadState = .running(stageText: "Downloading Parakeet V3...")
                    try await fluidAudioModelManager.downloadModel()

                    engineDownloadFraction = 1
                    engineDownloadState = .ready
                    settingsStore.saveTranscriptionEngine(.fluidAudio)

                    Task.detached(priority: .userInitiated) {
                        try? await LocalParakeetContextManager.shared.loadModel(version: .v3) { version in
                            try await AsrModels.loadFromCache(configuration: nil, version: version)
                        }
                    }

                case .localWhisper:
                    if try localWhisperModelManager.defaultModelReady() {
                        try localWhisperModelManager.removeDefaultEncoderIfPresent()
                        localWhisperModelManager.saveCustomModelPath(nil)
                        engineDownloadFraction = 1
                        engineDownloadState = .ready
                        settingsStore.saveTranscriptionEngine(.localWhisper)
                        return
                    }

                    engineDownloadState = .running(stageText: "Checking existing assets...")
                    try await localWhisperModelManager.installDefaultModel(
                        progress: { [weak self] stage in
                            Task { @MainActor [weak self, stage] in
                                let stageText =
                                    switch stage {
                                    case .checkingExistingAssets: "Checking assets..."
                                    case .downloadingModel: "Downloading Whisper..."
                                    case .ready: "Ready"
                                    }
                                self?.engineDownloadState = .running(stageText: stageText)
                            }
                        },
                        downloadProgress: { [weak self] fraction, completed, total in
                            Task { @MainActor [weak self, fraction, completed, total] in
                                self?.engineDownloadFraction = fraction
                                self?.engineBytesCompleted = completed
                                self?.engineBytesTotal = total
                            }
                        }
                    )

                    localWhisperModelManager.saveCustomModelPath(nil)
                    engineDownloadFraction = 1
                    engineDownloadState = .ready
                    settingsStore.saveTranscriptionEngine(.localWhisper)

                    // Trigger proactive high-priority background warm-up for Whisper
                    Task.detached(priority: .userInitiated) { [localWhisperModelManager] in
                        try? await localWhisperModelManager.installDefaultAssets()
                        try? await LocalWhisperWarmupCoordinator.shared.warmup()
                    }

                case .sherpaOnnxSenseVoice:
                    if sherpaOnnxSenseVoiceModelManager.isModelDownloaded() {
                        engineDownloadFraction = 1
                        engineDownloadState = .ready
                        settingsStore.saveTranscriptionEngine(.sherpaOnnxSenseVoice)
                        return
                    }

                    engineDownloadState = .running(stageText: "Downloading SenseVoice...")
                    try await sherpaOnnxSenseVoiceModelManager.installDefaultModel(
                        downloadProgress: { [weak self] fraction, completed, total in
                            Task { @MainActor [weak self, fraction, completed, total] in
                                self?.engineDownloadFraction = fraction
                                self?.engineBytesCompleted = completed
                                self?.engineBytesTotal = total
                            }
                        }
                    )

                    engineDownloadFraction = 1
                    engineDownloadState = .ready
                    settingsStore.saveTranscriptionEngine(.sherpaOnnxSenseVoice)
                }
            } catch {
                engineDownloadFraction = 0
                engineDownloadState = .failed(error.localizedDescription)
            }
        }

        func handleEngineDownloadPrimaryAction() async {
            if canContinueEngineDownload {
                continueOnboarding()
                return
            }

            switch engineDownloadState {
            case .idle, .failed:
                await prepareTranscriptionEngineIfNeeded()
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
            let stepString: String
            switch coordinator.onboardingStep {
            case .language: stepString = "language"
            case .permissions: stepString = "permissions"
            case .shortcut: stepString = "shortcut"
            case .firstSuccess: stepString = "first_success"
            case .appearance: stepString = "appearance"
            case .done: stepString = "done"
            }
            AnalyticsService.track("onboarding_step_completed", parameters: ["step": stepString])
            coordinator.advanceOnboarding()
        }

        func retreatOnboarding() {
            clearFlowMessages()
            coordinator.retreatOnboarding()
        }

        func finishOnboarding() {
            AnalyticsService.track("onboarding_step_completed", parameters: ["step": "done"])
            coordinator.finishOnboarding()
        }

        func updateShortcutSummary(_ shortcut: KeyboardShortcuts.Shortcut?) {
            shortcutSummaryText = shortcut.map { "\($0)" } ?? "Shortcut configured"
        }

        private func clearFlowMessages() {}

    }
#endif
