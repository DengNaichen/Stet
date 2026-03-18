#if os(macOS)
import AVFoundation
import AppKit
import Combine
import Foundation
import KeyboardShortcuts

@MainActor
final class MacAppModel: ObservableObject {
    typealias PrimaryActionSource = MacDictationWorkflowController.PrimaryActionSource
    typealias CaptureWorkflow = MacDictationWorkflowController.CaptureWorkflow

    private let textInjectionService: any TextInjectionService
    private let settingsStore: DictationSettingsStore
    private let workflowController: MacDictationWorkflowController
    private let shellPresentationController: MacShellPresentationController
    private let permissionGateController: MacPermissionGateController
    private let permissionManager: MacPermissionManager
    private let interactionSoundPlayer: InteractionSoundPlayer
    private var cancellables = Set<AnyCancellable>()
    private var stateResetTask: Task<Void, Never>?
    private var hotkeyInteraction = MacDictationHotkeyInteraction()
    private var previousDictationState: DictationState = .idle

    var dictationViewModel: DictationViewModel {
        workflowController.dictationViewModel
    }

    var isPanelVisible: Bool {
        shellPresentationController.isPanelVisible
    }

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
        let interactionSoundPlayer = InteractionSoundPlayer()
        let shellPresentationController = MacShellPresentationController()
        let permissionGateController = MacPermissionGateController()
        let bootstrapper = MacAppBootstrapper(settingsStore: settingsStore)
        self.textInjectionService = textInjectionService
        self.permissionManager = MacPermissionManager(textInjectionService: textInjectionService)
        self.settingsStore = settingsStore
        self.interactionSoundPlayer = interactionSoundPlayer
        self.shellPresentationController = shellPresentationController
        self.permissionGateController = permissionGateController
        let captureCoordinator = captureCoordinator ?? MacDictationCaptureCoordinator(
            clipboardService: clipboardService,
            textInjectionService: textInjectionService
        )
        self.workflowController = MacDictationWorkflowController(
            dictationViewModel: DictationViewModel(speechService: speechService),
            captureCoordinator: captureCoordinator,
            textInjectionService: textInjectionService,
            mediaPlaybackController: mediaPlaybackController,
            settingsStore: settingsStore,
            interactionSoundPlayer: interactionSoundPlayer
        )
        let launchConfiguration = bootstrapper.prepareForLaunch()
        dictationViewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        shellPresentationController.onVisibilityChange = { [weak self] in
            self?.objectWillChange.send()
        }
        bindState()
        bindLifecycleNotifications()
        registerHotkeys()
        applyDockVisibility(showInDock: launchConfiguration.showInDock)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            refreshPermissionIndicators()
        }
    }

    var statusText: String {
        guard hasRequiredPermissions else {
            return "Permissions Required"
        }

        return workflowController.statusText
    }

    var primaryButtonTitle: String {
        guard hasRequiredPermissions else {
            return "Grant Permissions"
        }

        switch dictationViewModel.state {
        case .idle:
            return "Start Dictation"
        case .listening:
            return "Stop Recording"
        case .processing:
            return "Processing"
        case .result, .error:
            return "Start Again"
        }
    }

    var panelButtonTitle: String {
        guard hasRequiredPermissions else {
            return "Open Permissions"
        }

        return isPanelVisible ? "Hide Capsule" : "Show Capsule"
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
        let providerName = settingsSnapshot.provider.displayName

        if settingsSnapshot.isRewriteEnabled {
            return "Use \(hotkeyAction) to capture audio"
        }

        return "Use \(hotkeyAction) to capture audio"
    }

    var processingStatusText: String {
        workflowController.processingStatusText
    }

    var hasRequiredPermissions: Bool {
        permissionManager.hasRequiredPermissions
    }

    var autoPasteStatusText: String {
        permissionManager.autoPasteStatusText
    }

    var speechRecognitionStatusText: String {
        permissionManager.speechRecognitionStatusText
    }

    var microphoneAccessStatusText: String {
        permissionManager.microphoneAccessStatusText
    }

    var microphoneAccessNeedsAttention: Bool {
        permissionManager.microphoneAccessNeedsAttention
    }

    var microphonePermissionActionTitle: String {
        permissionManager.microphonePermissionActionTitle
    }

    var autoPasteAccessNeedsAttention: Bool {
        permissionManager.autoPasteAccessNeedsAttention
    }

    var menuBarSymbolName: String {
        return "mic"
    }

    var stateAccentName: String {
        guard hasRequiredPermissions else {
            return "Permissions"
        }

        switch dictationViewModel.state {
        case .idle:
            return "Standby"
        case .listening:
            return "Live"
        case .processing:
            return "Finishing"
        case .result:
            return "Captured"
        case .error:
            return "Attention"
        }
    }

    var recordingLevel: Double {
        dictationViewModel.recordingLevel
    }

    func performPrimaryAction() {
        performPrimaryAction(source: .interface)
    }

    func cancelActiveCapture() {
        hotkeyInteraction.reset()
        workflowController.cancelActiveCapture()
        hidePanel()
    }

    func requestAutoPasteAccess() {
        permissionManager.requestAutoPasteAccess()
        refreshPermissionIndicators()
    }

    func resolveMicrophoneAccess() {
        if permissionManager.microphoneAccessStatus.canRequestInApp {
            requestMicrophoneAccess()
        } else {
            openMicrophoneSettings()
        }
    }

    func openAccessibilitySettings() {
        permissionManager.openAccessibilitySettings()
    }

    func openMicrophoneSettings() {
        permissionManager.openMicrophoneSettings()
    }

    private func performPrimaryAction(source: PrimaryActionSource) {
        switch dictationViewModel.state {
        case .idle, .result, .error:
            requestDictationCaptureStart(from: source)
        case .listening:
            requestDictationCaptureStopIfListening()
        case .processing:
            break
        }
    }

    private func handleHotkeyPressed() {
        let action = hotkeyInteraction.handleKeyDown(
            for: dictationViewModel.state,
            now: ProcessInfo.processInfo.systemUptime
        )
        performHotkeyAction(action)
    }

    private func handleHotkeyReleased() {
        let action = hotkeyInteraction.handleKeyUp(
            for: dictationViewModel.state,
            now: ProcessInfo.processInfo.systemUptime
        )
        performHotkeyAction(action)
    }

    func showPanel() {
        guard hasRequiredPermissions else {
            presentRequiredPermissionsGateIfNeeded()
            return
        }

        shellPresentationController.showPanel(appModel: self)
    }

    private func showTransientPanel() {
        shellPresentationController.showTransientPanel(appModel: self)
    }

    func hidePanel() {
        shellPresentationController.hidePanel()
    }

    func togglePanel() {
        guard hasRequiredPermissions || isPanelVisible else {
            presentRequiredPermissionsGateIfNeeded()
            return
        }

        shellPresentationController.togglePanel(appModel: self)
    }

    func panelDidHide() {
        shellPresentationController.panelDidHide()
    }

    func previewInteractionSound(_ preset: InteractionSoundPreset) {
        interactionSoundPlayer.playPreview(preset: preset)
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) throws {
        try MacAppBehaviorController.setLaunchAtLogin(enabled)
    }

    func applyDockVisibility(showInDock: Bool) {
        shellPresentationController.applyDockVisibility(showInDock: showInDock)
    }

    func openSettings(using action: () -> Void) {
        shellPresentationController.openSettings(
            currentShowInDockPreference: currentShowInDockPreference,
            using: action
        )
    }

    func settingsDidAppear() {
        shellPresentationController.settingsDidAppear(
            currentShowInDockPreference: currentShowInDockPreference
        )
    }

    func settingsDidDisappear() {
        shellPresentationController.settingsDidDisappear(
            currentShowInDockPreference: currentShowInDockPreference
        )
    }

    func refreshRuntimeFromSettings() {
        applyDockVisibility(showInDock: currentShowInDockPreference)
        objectWillChange.send()
    }

    private func bindState() {
        dictationViewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleDictationStateChange(state)
            }
            .store(in: &cancellables)
    }

    private func bindLifecycleNotifications() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshPermissionIndicators()
            }
            .store(in: &cancellables)
    }

    private func refreshPermissionIndicators() {
        if hasRequiredPermissions {
            permissionGateController.hide()
        } else {
            presentRequiredPermissionsGateIfNeeded()
        }

        objectWillChange.send()
    }



    private func handleDictationStateChange(_ state: DictationState) {
        handleStateTransitionObservation(for: state)
        handlePanelAndIdleLifecycle(for: state)
        handleResultLifecycle(for: state)
    }

    private func handleStateTransitionObservation(for state: DictationState) {
        let previousState = previousDictationState
        previousDictationState = state
        hotkeyInteraction.sync(with: state)
        cancelPendingStateTasks()
        workflowController.handleStateTransition(from: previousState, to: state)
    }

    private func handlePanelAndIdleLifecycle(for state: DictationState) {
        switch state {
        case .listening, .error:
            showTransientPanel()
        case .idle:
            guard workflowController.activeRecordingSource == nil else { return }
            workflowController.resetWorkflowIfNeeded()
            scheduleTransientPanelHideIfNeeded()
        case .processing, .result:
            break
        }
    }

    private func handleResultLifecycle(for state: DictationState) {
        guard case .result(let text) = state else { return }

        let completedWorkflow = workflowController.activeWorkflow
        Task { @MainActor [weak self] in
            guard let self else { return }
            await workflowController.handleCompletedResult(
                text: text,
                workflow: completedWorkflow,
                showTransientPanel: showTransientPanel
            )
        }

        scheduleStateReset()
    }

    private func cancelPendingStateTasks() {
        stateResetTask?.cancel()
        stateResetTask = nil
        shellPresentationController.cancelScheduledPanelHide()
    }

    private func scheduleStateReset() {
        stateResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self else { return }
            guard case .result = dictationViewModel.state else { return }
            dictationViewModel.send(.resetTapped)
        }
    }

    private func scheduleTransientPanelHideIfNeeded() {
        shellPresentationController.scheduleTransientPanelHideIfNeeded { [weak self] in
            self?.dictationViewModel.state ?? .idle
        }
    }

    private func registerHotkeys() {
        KeyboardShortcuts.removeHandler(for: .dictationHotkey)
        KeyboardShortcuts.onKeyDown(for: .dictationHotkey) { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleHotkeyPressed()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .dictationHotkey) { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleHotkeyReleased()
            }
        }
    }

    private func performHotkeyAction(_ action: MacDictationHotkeyInteraction.Action) {
        switch action {
        case .none:
            break
        case .startCapture:
            requestDictationCaptureStart(from: .hotkey)
        case .stopCapture:
            requestDictationCaptureStopIfListening()
        }
    }

    private func requestDictationCaptureStart(from source: PrimaryActionSource) {
        guard hasRequiredPermissions else {
            presentRequiredPermissionsGateIfNeeded()
            return
        }

        switch dictationViewModel.state {
        case .idle:
            startDictationCapture(from: source)
        case .result, .error:
            dictationViewModel.send(.resetTapped)
            startDictationCapture(from: source)
        case .listening, .processing:
            break
        }
    }

    private func startDictationCapture(from source: PrimaryActionSource) {
        workflowController.startDictationCapture(
            source: source,
            showTransientPanel: showTransientPanel
        )
    }

    private func requestDictationCaptureStopIfListening() {
        guard case .listening = dictationViewModel.state else { return }
        workflowController.stopActiveCapture()
    }

    private var settingsSnapshot: DictationSettingsSnapshot {
        settingsStore.loadSnapshot()
    }

    private var currentShowInDockPreference: Bool {
        UserDefaults.standard.object(forKey: MacPreferences.showInDock) as? Bool ?? false
    }

    private func presentRequiredPermissionsGateIfNeeded() {
        guard !hasRequiredPermissions else {
            permissionGateController.hide()
            return
        }

        if isPanelVisible {
            shellPresentationController.hidePanel()
        }

        permissionGateController.show(appModel: self)
    }

    private func requestMicrophoneAccess() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            AppLogger.info("Requesting microphone access from permissions gate", category: .permissions)
            _ = await permissionManager.requestMicrophonePermission()
            refreshPermissionIndicators()
        }
    }
}
#endif
