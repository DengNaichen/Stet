#if os(macOS)
    import Combine
    import Foundation
    import os
    import AppKit
    import StetVisuals

    @MainActor
    final class MacAppModel: ObservableObject, MacDictationCommandsCoordinating, MacSettingsShellCoordinating,
        MacAppPresentationModeling
    {
        static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.openwhispr.Stet",
            category: "dictation"
        )
        private let settingsStore: DictationSettingsStore
        private let sessionController: MacAppSessionController
        private let interactionSoundPlayer: InteractionSoundPlayer
        private let appearanceSettingsViewModel: MacAppearanceSettingsViewModel
        private let mcpServerController: StetMCPServerController?
        private var passiveListeningRuntime: MacPassiveListeningRuntime?

        @Published private(set) var passiveListeningState: MacPassiveListeningState =
            .unavailable("Preparing passive listening")

        private var cancellables = Set<AnyCancellable>()

        convenience init() {
            let settingsStore = DictationSettingsStore()
            let captureService = MacAudioCaptureService()
            let passiveListeningRuntime = MacPassiveListeningRuntime(captureService: captureService)
            let pasteboardRestoreCoordinator = PasteboardRestoreCoordinator()
            let clipboardService = SystemClipboardService()
            let textInjectionService = SystemTextInjectionService(
                clipboardService: clipboardService,
                pasteboardRestoreCoordinator: pasteboardRestoreCoordinator
            )
            self.init(
                speechService: ConfigurableSpeechService.live(
                    settingsStore: settingsStore,
                    captureService: captureService,
                    beginActiveCapture: { await passiveListeningRuntime.beginActive() },
                    resumePassiveCapture: { await passiveListeningRuntime.resumePassive() }
                ),
                clipboardService: clipboardService,
                textInjectionService: textInjectionService,
                mediaPlaybackController: MacMediaPlaybackController(),
                systemAudioMuting: SystemAudioMuteController(),
                settingsStore: settingsStore,
                captureCoordinator: MacDictationCaptureCoordinator(
                    clipboardService: clipboardService,
                    textInjectionService: textInjectionService,
                    pasteboardRestoreCoordinator: pasteboardRestoreCoordinator
                ),
                mcpServerController: StetMCPServerController.live(settingsStore: settingsStore),
                passiveListeningRuntime: passiveListeningRuntime
            )
        }

        init(
            speechService: any SpeechService,
            clipboardService: any ClipboardService,
            textInjectionService: any TextInjectionService,
            mediaPlaybackController: any MediaPlaybackControlling,
            systemAudioMuting: (any SystemAudioMuting)? = nil,
            settingsStore: DictationSettingsStore = DictationSettingsStore(),
            captureCoordinator: MacDictationCaptureCoordinator? = nil,
            mcpServerController: StetMCPServerController? = nil,
            passiveListeningRuntime: MacPassiveListeningRuntime? = nil
        ) {
            let bootstrapper = MacAppBootstrapper(settingsStore: settingsStore)
            let captureCoordinator =
                captureCoordinator
                ?? MacDictationCaptureCoordinator(
                    clipboardService: clipboardService,
                    textInjectionService: textInjectionService
                )
            let interactionSoundPlayer = InteractionSoundPlayer()
            let workflowController = MacDictationWorkflowController(
                dictationViewModel: DictationViewModel(speechService: speechService),
                captureCoordinator: captureCoordinator,
                mediaPlaybackController: mediaPlaybackController,
                systemAudioMuting: systemAudioMuting,
                settingsStore: settingsStore,
                interactionSoundPlayer: interactionSoundPlayer,
                statsModel: .shared
            )
            let sessionController = MacAppSessionController(
                workflowController: workflowController,
                permissionManager: MacPermissionManager(textInjectionService: textInjectionService),
                pipelineFactory: .live()
            )
            self.settingsStore = settingsStore
            self.sessionController = sessionController
            self.interactionSoundPlayer = interactionSoundPlayer
            self.appearanceSettingsViewModel = .shared
            self.mcpServerController = mcpServerController
            let launchConfiguration = bootstrapper.prepareForLaunch()
            sessionController.onChange = { [weak self] in
                self?.objectWillChange.send()
            }

            appearanceSettingsViewModel.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
            sessionController.activate(presentationModel: self, showInDock: launchConfiguration.showInDock)
            mcpServerController?.startIfEnabled()

            if let passiveListeningRuntime {
                self.passiveListeningRuntime = passiveListeningRuntime
                Task { [weak self] in
                    await passiveListeningRuntime.setStateHandler { [weak self] state in
                        self?.passiveListeningState = state
                    }
                    guard self != nil else { return }
                    await passiveListeningRuntime.start()
                }
                NotificationCenter.default.publisher(for: .speakerProfilesDidChange)
                    .receive(on: DispatchQueue.main)
                    .sink { _ in
                        Task { await passiveListeningRuntime.restart() }
                    }
                    .store(in: &cancellables)
                NotificationCenter.default.publisher(
                    for: AudioDeviceChangeMonitor.devicesDidChangeNotification
                )
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    Task { await passiveListeningRuntime.restart() }
                }
                .store(in: &cancellables)
                NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
                    .receive(on: DispatchQueue.main)
                    .sink { _ in
                        Task { await passiveListeningRuntime.revalidatePermission() }
                    }
                    .store(in: &cancellables)
            }
        }

        deinit {
            let passiveListeningRuntime = passiveListeningRuntime
            Task { await passiveListeningRuntime?.stop() }
        }

        var updates: AnyPublisher<Void, Never> {
            objectWillChange.eraseToAnyPublisher()
        }

        var statusText: String {
            guard hasRequiredPermissions else {
                return "Permissions Required"
            }

            return sessionController.statusText
        }

        var primaryButtonTitle: String {
            guard hasRequiredPermissions else {
                return "Grant Permissions"
            }

            switch dictationState {
            case .idle:
                return "Start Dictation"
            case .starting:
                if recordingLevel > 0 {
                    return "Stop Recording"
                }
                return "Starting..."
            case .listening:
                return "Stop Recording"
            case .processing:
                return "Processing"
            case .clipboardPending:
                return "Copy to Clipboard"
            case .result, .error:
                return "Start Again"
            }
        }

        var panelButtonTitle: String {
            guard hasRequiredPermissions else {
                return "Open Permissions"
            }

            return sessionController.isPanelVisible ? "Hide Capsule" : "Show Capsule"
        }

        var rewriteButtonTitle: String {
            "Rewrite"
        }

        var idleHintText: String {
            let hotkeyAction = "use"

            if settingsSnapshot.isRewriteEnabled {
                return "Use \(hotkeyAction) to capture audio"
            }

            return "Use \(hotkeyAction) to capture audio"
        }

        var processingStatusText: String {
            sessionController.processingStatusText
        }

        var hasRequiredPermissions: Bool {
            sessionController.hasRequiredPermissions
        }

        var autoPasteStatusText: String {
            sessionController.autoPasteStatusText
        }

        var speechRecognitionStatusText: String {
            sessionController.speechRecognitionStatusText
        }

        var microphoneAccessStatusText: String {
            sessionController.microphoneAccessStatusText
        }

        var microphoneAccessNeedsAttention: Bool {
            sessionController.microphoneAccessNeedsAttention
        }

        var microphonePermissionActionTitle: String {
            sessionController.microphonePermissionActionTitle
        }

        var autoPasteAccessNeedsAttention: Bool {
            sessionController.autoPasteAccessNeedsAttention
        }

        var onboardingStep: MacOnboardingStep {
            sessionController.onboardingStep
        }

        var onboardingMode: MacOnboardingMode? {
            sessionController.onboardingMode
        }

        var shortcutTestDetectedPress: Bool {
            sessionController.shortcutTestDetectedPress
        }

        var shortcutTestCompletedRoundTrip: Bool {
            sessionController.shortcutTestCompletedRoundTrip
        }

        var shortcutTestPreviewText: String? {
            sessionController.shortcutTestPreviewText
        }

        var canContinueShortcutOnboarding: Bool {
            sessionController.canContinueShortcutOnboarding
        }

        var firstSuccessPreviewText: String? {
            sessionController.firstSuccessPreviewText
        }

        var firstSuccessFailureMessage: String? {
            sessionController.firstSuccessFailureMessage
        }

        var canContinueFirstSuccessOnboarding: Bool {
            sessionController.canContinueFirstSuccessOnboarding
        }

        var canSkipFirstSuccessOnboarding: Bool {
            sessionController.canSkipFirstSuccessOnboarding
        }

        var canFinishAppearanceOnboarding: Bool {
            appearanceSettingsViewModel.hasAppliedSelectedTheme
        }

        var menuBarSymbolName: String {
            return "mic"
        }

        var passiveListeningStatusText: String {
            switch passiveListeningState {
            case .unavailable(let reason):
                return "Passive unavailable: \(reason)"
            case .passiveArmed:
                return "Passive microphone active"
            case .passivePending:
                return "Checking nearby speech"
            case .passiveRelevant:
                return "Recording relevant conversation"
            case .active:
                return "Active dictation"
            }
        }

        var isPassiveMicrophoneActive: Bool {
            switch passiveListeningState {
            case .passiveArmed, .passivePending, .passiveRelevant:
                true
            case .unavailable, .active:
                false
            }
        }

        var stateAccentName: String {
            guard hasRequiredPermissions else {
                return "Permissions"
            }

            switch dictationState {
            case .idle:
                return "Standby"
            case .starting:
                return "Starting"
            case .listening:
                return "Live"
            case .processing:
                return "Finishing"
            case .clipboardPending:
                return "Copy"
            case .result:
                return "Captured"
            case .error:
                return "Attention"
            }
        }

        var dictationState: DictationState {
            sessionController.dictationState
        }

        var recordingLevel: Double {
            sessionController.recordingLevel
        }

        var audioFeatures: MacDictationCapsuleVisualSignals {
            sessionController.audioFeatures
        }

        var detectedTargetApplication: AppInfo? {
            sessionController.detectedTargetApplication
        }

        func performPrimaryAction() {
            sessionController.performPrimaryAction()
        }

        func cancelActiveCapture() {
            sessionController.cancelActiveCapture()
        }

        func requestAutoPasteAccess() {
            sessionController.requestAutoPasteAccess()
        }

        func resolveMicrophoneAccess() {
            sessionController.resolveMicrophoneAccess()
        }

        func openAccessibilitySettings() {
            sessionController.openAccessibilitySettings()
        }

        func chooseOnboardingMode(_ mode: MacOnboardingMode) {
            sessionController.chooseOnboardingMode(mode)
        }

        func selectOnboardingAppearanceTheme(_ theme: MacDictationVisualTheme) {
            appearanceSettingsViewModel.updateShaderTheme(theme, persist: false)
        }

        func applyOnboardingAppearanceTheme() {
            appearanceSettingsViewModel.applySelectedTheme()
        }

        func advanceOnboarding() {
            sessionController.advanceOnboarding()
        }

        func retreatOnboarding() {
            sessionController.retreatOnboarding()
        }

        func finishOnboarding() {
            sessionController.finishOnboarding()
        }

        func openMicrophoneSettings() {
            sessionController.openMicrophoneSettings()
        }

        func showPanel() {
            sessionController.showPanel()
        }

        func hidePanel() {
            sessionController.hidePanel()
        }

        func dismissPendingCopy() {
            sessionController.dismissPendingCopy()
        }

        func togglePanel() {
            sessionController.togglePanel()
        }

        func previewInteractionSound(_ preset: InteractionSoundPreset) {
            interactionSoundPlayer.playPreview(preset: preset)
        }

        func setLaunchAtLoginEnabled(_ enabled: Bool) throws {
            try MacAppBehaviorController.setLaunchAtLogin(enabled)
        }

        func applyDockVisibility(showInDock: Bool) {
            sessionController.applyDockVisibility(showInDock: showInDock)
        }

        var isDebugForceOnboardingEnabled: Bool {
            UserDefaults.standard.bool(forKey: MacPreferences.debugForceOnboarding)
        }

        func setDebugForceOnboardingEnabled(_ enabled: Bool) {
            sessionController.setDebugForceOnboardingEnabled(enabled)
        }

        func resetOnboardingForDebug() {
            sessionController.resetOnboardingForDebug()
        }

        func openSettings(using action: () -> Void) {
            sessionController.openSettings(using: action)
        }

        func settingsDidAppear() {
            sessionController.settingsDidAppear()
        }

        func settingsDidDisappear() {
            sessionController.settingsDidDisappear()
        }

        func refreshRuntimeFromSettings() {
            sessionController.refreshRuntimeFromSettings()
        }

        func handleDeepLink(_ url: URL) {
            Self.logger.info("Received deep link: \(url.absoluteString)")
        }

        private var settingsSnapshot: DictationSettingsSnapshot {
            settingsStore.loadSnapshot()
        }
    }
#endif
