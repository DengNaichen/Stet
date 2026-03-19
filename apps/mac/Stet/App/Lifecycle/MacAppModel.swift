#if os(macOS)
import Combine
import Foundation

@MainActor
final class MacAppModel: ObservableObject, MacDictationCommandsCoordinating, MacSettingsShellCoordinating, MacAppPresentationModeling {
    private let settingsStore: DictationSettingsStore
    private let sessionController: MacAppSessionController
    private let interactionSoundPlayer: InteractionSoundPlayer

    convenience init() {
        let settingsStore = DictationSettingsStore()
        let clipboardService = SystemClipboardService()
        let textInjectionService = SystemTextInjectionService(clipboardService: clipboardService)
        self.init(
            speechService: ConfigurableSpeechService.live(settingsStore: settingsStore),
            clipboardService: clipboardService,
            textInjectionService: textInjectionService,
            mediaPlaybackController: MacMediaPlaybackController(),
            settingsStore: settingsStore,
            captureCoordinator: MacDictationCaptureCoordinator(
                clipboardService: clipboardService,
                textInjectionService: textInjectionService
            )
        )
    }

    init(
        speechService: any SpeechService,
        clipboardService: any ClipboardService,
        textInjectionService: any TextInjectionService,
        mediaPlaybackController: any MediaPlaybackControlling,
        settingsStore: DictationSettingsStore = DictationSettingsStore(),
        captureCoordinator: MacDictationCaptureCoordinator? = nil
    ) {
        let bootstrapper = MacAppBootstrapper(settingsStore: settingsStore)
        let captureCoordinator = captureCoordinator ?? MacDictationCaptureCoordinator(
            clipboardService: clipboardService,
            textInjectionService: textInjectionService
        )
        let interactionSoundPlayer = InteractionSoundPlayer()
        let workflowController = MacDictationWorkflowController(
            dictationViewModel: DictationViewModel(speechService: speechService),
            captureCoordinator: captureCoordinator,
            textInjectionService: textInjectionService,
            mediaPlaybackController: mediaPlaybackController,
            settingsStore: settingsStore,
            interactionSoundPlayer: interactionSoundPlayer
        )
        let sessionController = MacAppSessionController(
            workflowController: workflowController,
            permissionManager: MacPermissionManager(textInjectionService: textInjectionService)
        )
        self.settingsStore = settingsStore
        self.sessionController = sessionController
        self.interactionSoundPlayer = interactionSoundPlayer
        let launchConfiguration = bootstrapper.prepareForLaunch()
        sessionController.onChange = { [weak self] in
            self?.objectWillChange.send()
        }
        sessionController.activate(presentationModel: self, showInDock: launchConfiguration.showInDock)
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

    var translationButtonTitle: String {
        "Translate"
    }

    var rewriteButtonTitle: String {
        "Rewrite"
    }

    var currentTranslationTargetLanguage: TranslationTargetLanguage {
        settingsSnapshot.translationTargetLanguage
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

    var relaySessionEmail: String? {
        sessionController.relaySessionEmail
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

    var menuBarSymbolName: String {
        return "mic"
    }

    var stateAccentName: String {
        guard hasRequiredPermissions else {
            return "Permissions"
        }

        switch dictationState {
        case .idle:
            return "Standby"
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

    func advanceOnboarding() {
        sessionController.advanceOnboarding()
    }

    func retreatOnboarding() {
        sessionController.retreatOnboarding()
    }

    func completeAPIKeyOnboarding(provider: DictationProvider) {
        settingsStore.saveExecutionMode(.byok)
        settingsStore.saveProvider(provider)
        sessionController.completeCredentialOnboarding(mode: .apiKey)
    }

    func completeManagedOnboarding() {
        settingsStore.saveExecutionMode(.managed)
        sessionController.completeCredentialOnboarding(mode: .managed)
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

    private var settingsSnapshot: DictationSettingsSnapshot {
        settingsStore.loadSnapshot()
    }
}
#endif
