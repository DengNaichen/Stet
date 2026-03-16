#if os(macOS)
import AVFoundation
import AppKit
import ApplicationServices
import Carbon
import Combine
import Foundation
import KeyboardShortcuts

@MainActor
final class MacAppModel: ObservableObject {
    private enum LegacyPreferenceKey {
        static let copyLatestCaptureHotkeyShortcut = "mac.copyLatestCaptureHotkeyShortcut"
        static let historyRetentionPeriod = "mac.historyRetentionPeriod"
    }

    typealias PrimaryActionSource = MacDictationWorkflowController.PrimaryActionSource
    typealias CaptureWorkflow = MacDictationWorkflowController.CaptureWorkflow

    private let textInjectionService: any TextInjectionService
    private let settingsStore: DictationSettingsStore
    private let workflowController: MacDictationWorkflowController
    private let shellPresentationController: MacShellPresentationController
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
            speechService: ConfigurableSpeechService(settingsStore: settingsStore),
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
        self.textInjectionService = textInjectionService
        self.settingsStore = settingsStore
        self.interactionSoundPlayer = interactionSoundPlayer
        self.shellPresentationController = shellPresentationController
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
        configureDefaults()
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
        registerHotkeys()
        shellPresentationController.applyInitialDockVisibility()

        if UserDefaults.standard.bool(forKey: MacPreferences.showPanelOnLaunch) {
            DispatchQueue.main.async { [weak self] in
                self?.showPanel()
            }
        }
    }

    var statusText: String {
        workflowController.statusText
    }

    var primaryButtonTitle: String {
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
        isPanelVisible ? "Hide Capsule" : "Show Capsule"
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

    var transcriptionProviderName: String {
        settingsSnapshot.provider.displayName
    }

    var pipelineDescription: String {
        settingsSnapshot.provider.pipelineDescription
    }

    var rewriteStatusText: String {
        settingsSnapshot.isRewriteEnabled ? "Enabled" : "Disabled"
    }

    var openAIStatusText: String {
        settingsSnapshot.isOpenAIConfigured ? "Configured" : "Missing Credential"
    }

    var idleHintText: String {
        let hotkeyAction = "use"

        if settingsSnapshot.isRewriteEnabled {
            return "Use the main button or \(hotkeyAction) the hotkey to capture audio, send it to OpenAI for transcription, and then rewrite the final text."
        }

        return "Use the main button or \(hotkeyAction) the hotkey to capture audio and send it to OpenAI for transcription."
    }

    var processingStatusText: String {
        workflowController.processingStatusText
    }

    var autoPasteStatusText: String {
        let state = textInjectionService.accessState

        switch (state.hasAccessibilityAccess, state.hasPostEventAccess) {
        case (true, true):
            return "Enabled"
        case (true, false):
            return "Accessibility Only"
        case (false, true):
            return "Input Injection Only"
        case (false, false):
            return "Needs Access"
        }
    }

    var speechRecognitionStatusText: String {
        "Not Required"
    }

    var microphoneAccessStatusText: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return "Allowed"
        case .notDetermined:
            return "Not Requested"
        case .denied, .restricted:
            return "Needs Access"
        @unknown default:
            return "Unknown"
        }
    }

    var microphoneAccessNeedsAttention: Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            return true
        case .authorized, .notDetermined:
            return false
        @unknown default:
            return true
        }
    }

    var autoPasteAccessNeedsAttention: Bool {
        !textInjectionService.accessState.canSimulateInput
    }

    var inputMonitoringStatusText: String {
        inputMonitoringGranted ? "Allowed" : "Needs Access"
    }

    var inputMonitoringNeedsAttention: Bool {
        false
    }

    var menuBarSymbolName: String {
        switch dictationViewModel.state {
        case .idle:
            return "mic"
        case .listening:
            return "waveform.badge.mic"
        case .processing:
            return "hourglass"
        case .result:
            return "checkmark.bubble"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    var stateAccentName: String {
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
        textInjectionService.requestAccess()
    }

    func openAccessibilitySettings() {
        textInjectionService.openAccessibilitySettings()
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func requestInputMonitoringAccess() {
        if #available(macOS 10.15, *) {
            _ = CGRequestListenEventAccess()
        }
    }

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }

        NSWorkspace.shared.open(url)
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
        shellPresentationController.showPanel(appModel: self)
    }

    private func showTransientPanel() {
        shellPresentationController.showTransientPanel(appModel: self)
    }

    func hidePanel() {
        shellPresentationController.hidePanel()
    }

    func togglePanel() {
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

    private func configureDefaults() {
        removeLegacyHistoryArtifacts()

        if UserDefaults.standard.object(forKey: MacPreferences.showPanelOnLaunch) == nil {
            UserDefaults.standard.set(false, forKey: MacPreferences.showPanelOnLaunch)
        }

        if UserDefaults.standard.object(forKey: MacPreferences.copyToClipboardOnCapture) == nil {
            UserDefaults.standard.set(true, forKey: MacPreferences.copyToClipboardOnCapture)
        }

        if UserDefaults.standard.object(forKey: MacPreferences.autoPasteOnCapture) == nil {
            UserDefaults.standard.set(true, forKey: MacPreferences.autoPasteOnCapture)
        }

        if UserDefaults.standard.object(forKey: MacPreferences.revealPanelOnCapture) == nil {
            UserDefaults.standard.set(false, forKey: MacPreferences.revealPanelOnCapture)
        }

        if UserDefaults.standard.object(forKey: MacPreferences.pauseMediaDuringDictation) == nil {
            UserDefaults.standard.set(false, forKey: MacPreferences.pauseMediaDuringDictation)
        }

        if UserDefaults.standard.object(forKey: MacPreferences.selectedAudioInputDeviceID) == nil {
            UserDefaults.standard.set(0, forKey: MacPreferences.selectedAudioInputDeviceID)
        }

        if UserDefaults.standard.object(forKey: MacPreferences.transcriptionProvider) == nil {
            UserDefaults.standard.set(DictationProvider.openAI.rawValue, forKey: MacPreferences.transcriptionProvider)
        }

        if UserDefaults.standard.object(forKey: MacPreferences.rewriteEnabled) == nil {
            UserDefaults.standard.set(false, forKey: MacPreferences.rewriteEnabled)
        }

        if UserDefaults.standard.string(forKey: MacPreferences.translationTargetLanguage) == nil {
            settingsStore.saveTranslationTargetLanguage(.english)
        }

        if UserDefaults.standard.object(forKey: MacPreferences.translateSelectedTextOnTranslationHotkey) == nil {
            settingsStore.saveTranslateSelectedTextOnTranslationHotkey(true)
        }

        if UserDefaults.standard.string(forKey: MacPreferences.openAITranslationModel) == nil {
            UserDefaults.standard.set("gpt-5-mini", forKey: MacPreferences.openAITranslationModel)
        }

        if UserDefaults.standard.object(forKey: MacPreferences.hotkeyDistinguishModifierSides) == nil {
            settingsStore.saveHotkeyDistinguishModifierSides(false)
        }

        if UserDefaults.standard.object(forKey: MacPreferences.interactionSoundsEnabled) == nil {
            UserDefaults.standard.set(true, forKey: MacPreferences.interactionSoundsEnabled)
        }

        if UserDefaults.standard.string(forKey: MacPreferences.interactionSoundPreset) == nil {
            UserDefaults.standard.set(InteractionSoundPreset.soft.rawValue, forKey: MacPreferences.interactionSoundPreset)
        }

        if UserDefaults.standard.object(forKey: MacPreferences.launchAtLogin) == nil {
            UserDefaults.standard.set(MacAppBehaviorController.launchAtLoginIsEnabled(), forKey: MacPreferences.launchAtLogin)
        }

        if UserDefaults.standard.object(forKey: MacPreferences.showInDock) == nil {
            UserDefaults.standard.set(false, forKey: MacPreferences.showInDock)
        }

        if UserDefaults.standard.string(forKey: MacPreferences.proxyMode) == nil {
            UserDefaults.standard.set(NetworkProxyMode.system.rawValue, forKey: MacPreferences.proxyMode)
        }

        if UserDefaults.standard.string(forKey: MacPreferences.customProxyScheme) == nil {
            UserDefaults.standard.set(CustomProxyScheme.http.rawValue, forKey: MacPreferences.customProxyScheme)
        }

        if UserDefaults.standard.object(forKey: MacPreferences.hotkeyDebugLoggingEnabled) == nil {
            UserDefaults.standard.set(false, forKey: MacPreferences.hotkeyDebugLoggingEnabled)
        }

        if UserDefaults.standard.object(forKey: MacPreferences.openAIDebugLoggingEnabled) == nil {
            UserDefaults.standard.set(false, forKey: MacPreferences.openAIDebugLoggingEnabled)
        }
    }

    private func removeLegacyHistoryArtifacts() {
        let fileManager = FileManager.default
        UserDefaults.standard.removeObject(forKey: LegacyPreferenceKey.copyLatestCaptureHotkeyShortcut)
        UserDefaults.standard.removeObject(forKey: LegacyPreferenceKey.historyRetentionPeriod)

        if let applicationSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            let historyURL = applicationSupport
                .appendingPathComponent("airType", isDirectory: true)
                .appendingPathComponent("transcription-history.json")
            try? fileManager.removeItem(at: historyURL)
        }

        let temporaryHistoryURL = fileManager.temporaryDirectory.appendingPathComponent("airType-transcription-history.json")
        try? fileManager.removeItem(at: temporaryHistoryURL)
    }

    private var settingsSnapshot: DictationSettingsSnapshot {
        settingsStore.loadSnapshot()
    }

    private var currentShowInDockPreference: Bool {
        UserDefaults.standard.object(forKey: MacPreferences.showInDock) as? Bool ?? false
    }

    private var inputMonitoringGranted: Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess()
        }

        return true
    }
}
#endif
