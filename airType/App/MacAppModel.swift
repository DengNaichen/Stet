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
    enum PrimaryActionSource {
        case interface
        case hotkey
    }

    private struct FocusedAppSnapshot {
        let bundleID: String?
        let appName: String?
    }

    private enum CaptureWorkflow: Equatable {
        case dictation
        case translationFromSpeech
        case translationFromSelection(sourceText: String)
        case rewriteFromSelection(sourceText: String)

        var isSelectionReplacement: Bool {
            switch self {
            case .translationFromSelection, .rewriteFromSelection:
                return true
            case .dictation, .translationFromSpeech:
                return false
            }
        }
    }

    private enum PanelPresentationMode {
        case manual
        case transient
    }

    @Published private(set) var history: [TranscriptionRecord] = []
    @Published private(set) var isPanelVisible = false
    @Published private(set) var lastCopiedRecordID: UUID?

    let dictationViewModel: DictationViewModel

    private let clipboardService: any ClipboardService
    private let textInjectionService: any TextInjectionService
    private let mediaPlaybackController: any MediaPlaybackControlling
    private let settingsStore: DictationSettingsStore
    private let captureCoordinator: MacDictationCaptureCoordinator
    private let panelController = MacPanelController()
    private let interactionSoundPlayer = InteractionSoundPlayer()
    private var cancellables = Set<AnyCancellable>()
    private var stateResetTask: Task<Void, Never>?
    private var panelHideTask: Task<Void, Never>?
    private weak var lastTargetApplication: NSRunningApplication?
    private var activeRecordingSource: PrimaryActionSource?
    private var activeWorkflow: CaptureWorkflow = .dictation
    private var activeContextSnapshot: FocusedAppSnapshot?
    private var panelPresentationMode: PanelPresentationMode = .manual
    private var previousDictationState: DictationState = .idle
    private var isSettingsVisible = false
    private var shouldRestoreAccessoryModeAfterSettings = false

    convenience init() {
        let settingsStore = DictationSettingsStore()
        let clipboardService = SystemClipboardService()
        let textInjectionService = SystemTextInjectionService(clipboardService: clipboardService)
        let historyStore = FileTranscriptionHistoryStore()
        self.init(
            speechService: ConfigurableSpeechService(settingsStore: settingsStore),
            clipboardService: clipboardService,
            textInjectionService: textInjectionService,
            historyStore: historyStore,
            mediaPlaybackController: MacMediaPlaybackController(),
            settingsStore: settingsStore,
            captureCoordinator: MacDictationCaptureCoordinator(
                clipboardService: clipboardService,
                textInjectionService: textInjectionService,
                historyStore: historyStore
            )
        )
    }

    init(
        speechService: any SpeechService,
        clipboardService: any ClipboardService,
        textInjectionService: any TextInjectionService,
        historyStore: any TranscriptionHistoryStore,
        mediaPlaybackController: any MediaPlaybackControlling,
        settingsStore: DictationSettingsStore = DictationSettingsStore(),
        captureCoordinator: MacDictationCaptureCoordinator? = nil
    ) {
        self.dictationViewModel = DictationViewModel(speechService: speechService)
        self.clipboardService = clipboardService
        self.textInjectionService = textInjectionService
        self.mediaPlaybackController = mediaPlaybackController
        self.settingsStore = settingsStore
        self.captureCoordinator = captureCoordinator ?? MacDictationCaptureCoordinator(
            clipboardService: clipboardService,
            textInjectionService: textInjectionService,
            historyStore: historyStore
        )
        configureDefaults()
        restoreHistory()
        dictationViewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        bindState()
        registerHotkeys()
        MacAppBehaviorController.applyDockVisibility(
            showInDock: UserDefaults.standard.object(forKey: MacPreferences.showInDock) as? Bool ?? false
        )

        if UserDefaults.standard.bool(forKey: MacPreferences.showPanelOnLaunch) {
            DispatchQueue.main.async { [weak self] in
                self?.showPanel()
            }
        }
    }

    var statusText: String {
        switch dictationViewModel.state {
        case .idle:
            return "Ready"
        case .listening:
            switch activeWorkflow {
            case .rewriteFromSelection:
                return "Listening for rewrite instructions..."
            case .translationFromSpeech:
                return "Listening for translation..."
            case .dictation, .translationFromSelection:
                return "Listening..."
            }
        case .processing:
            switch activeWorkflow {
            case .translationFromSpeech, .translationFromSelection:
                return "Translating..."
            case .rewriteFromSelection:
                return "Rewriting selected text..."
            case .dictation:
                return "Processing..."
            }
        case .result:
            switch activeWorkflow {
            case .translationFromSpeech, .translationFromSelection:
                return "Translation complete"
            case .rewriteFromSelection:
                return "Rewrite complete"
            case .dictation:
                return "Transcription complete"
            }
        case .error:
            return "Something went wrong"
        }
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

    var copyButtonTitle: String {
        lastCopiedRecordID == latestRecord?.id ? "Copied Latest" : "Copy Latest"
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
        switch activeWorkflow {
        case .translationFromSpeech, .translationFromSelection:
            return "Translating with OpenAI..."
        case .rewriteFromSelection:
            return "Rewriting selected text with OpenAI..."
        case .dictation:
            break
        }

        return settingsSnapshot.isRewriteEnabled
            ? "Transcribing with OpenAI and rewriting..."
            : "Transcribing with OpenAI..."
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

    var latestRecord: TranscriptionRecord? {
        history.first
    }

    var recordingLevel: Double {
        dictationViewModel.recordingLevel
    }

    var hasHistory: Bool {
        !history.isEmpty
    }

    var displayedHistory: [TranscriptionRecord] {
        Array(history.prefix(20))
    }

    var allHistory: [TranscriptionRecord] {
        history
    }

    var historyCount: Int {
        history.count
    }

    var historyRetentionPeriod: HistoryRetentionPeriod {
        settingsStore.loadHistoryRetentionPeriod()
    }

    func performPrimaryAction() {
        performPrimaryAction(source: .interface)
    }

    func cancelActiveCapture() {
        activeRecordingSource = nil
//        activeHotkeyAction = nil
        dictationViewModel.send(.resetTapped)
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
        case .idle:
            startDictationCapture(source: source)
        case .listening:
            activeRecordingSource = nil
            dictationViewModel.stopCapture()
        case .processing:
            break
        case .result, .error:
            dictationViewModel.send(.resetTapped)
            startDictationCapture(source: source)
        }
    }

    private func handleHotkeyPressed() {
        performPrimaryAction(source: .hotkey)
    }

    private func handleHotkeyReleased() {
        // Dictation hotkey currently uses press-to-toggle behavior.
    }

    func showPanel() {
        showPanel(mode: .manual)
    }

    private func showTransientPanel() {
        showPanel(mode: .transient)
    }

    private func showPanel(mode: PanelPresentationMode) {
        activeContextSnapshot = captureTargetApplicationSnapshot()
        panelPresentationMode = mode
        panelController.show(
            appModel: self,
            mode: mode == .manual ? .manual : .transient
        )
        isPanelVisible = true
    }

    func hidePanel() {
        panelHideTask?.cancel()
        panelHideTask = nil
        panelController.hide()
        isPanelVisible = false
        panelPresentationMode = .manual
    }

    func togglePanel() {
        if isPanelVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func panelDidHide() {
        isPanelVisible = false
        panelPresentationMode = .manual
    }

    func clearHistory() {
        history.removeAll()
        lastCopiedRecordID = nil
        persistHistory()
    }

    func deleteHistoryRecord(_ record: TranscriptionRecord) {
        history.removeAll { $0.id == record.id }

        if lastCopiedRecordID == record.id {
            lastCopiedRecordID = nil
        }

        persistHistory()
    }

    func copyLatestToClipboard() {
        guard let latestRecord else { return }
        copyToClipboard(record: latestRecord)
    }

    func copyToClipboard(record: TranscriptionRecord) {
        clipboardService.copy(record.text)
        lastCopiedRecordID = record.id
    }

    func previewInteractionSound(_ preset: InteractionSoundPreset) {
        interactionSoundPlayer.playPreview(preset: preset)
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) throws {
        try MacAppBehaviorController.setLaunchAtLogin(enabled)
    }

    func applyDockVisibility(showInDock: Bool) {
        if showInDock {
            shouldRestoreAccessoryModeAfterSettings = false
            MacAppBehaviorController.applyDockVisibility(showInDock: true)
            return
        }

        if isSettingsVisible {
            shouldRestoreAccessoryModeAfterSettings = true
            MacAppBehaviorController.applyDockVisibility(showInDock: true)
            return
        }

        shouldRestoreAccessoryModeAfterSettings = false
        MacAppBehaviorController.applyDockVisibility(showInDock: false)
    }

    func openSettings(using action: () -> Void) {
        prepareForSettingsPresentation()
        action()
    }

    func settingsDidAppear() {
        isSettingsVisible = true
        prepareForSettingsPresentation()
    }

    func settingsDidDisappear() {
        isSettingsVisible = false
        applyDockVisibility(showInDock: currentShowInDockPreference)
    }

    func refreshRuntimeFromSettings() {
        applyDockVisibility(showInDock: currentShowInDockPreference)
        objectWillChange.send()
    }

    func refreshHistory() {
        restoreHistory()
    }

    private func bindState() {
        dictationViewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                let previousState = previousDictationState
                previousDictationState = state
                stateResetTask?.cancel()
                stateResetTask = nil
                panelHideTask?.cancel()
                panelHideTask = nil
                handleMediaTransition(from: previousState, to: state)

                if case .listening = state {
                    showTransientPanel()
                } else {
                    activeRecordingSource = nil
                }

                if case .result(let text) = state {
                    let completedWorkflow = activeWorkflow
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let outcome = await handleCompletedResult(
                            text: text,
                            workflow: completedWorkflow
                        )

                        history = outcome.history
                        lastCopiedRecordID = outcome.copiedRecordID
                    }

                    stateResetTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(900))
                        guard let self else { return }
                        guard case .result = dictationViewModel.state else { return }
                        dictationViewModel.send(.resetTapped)
                    }
                } else if case .error = state {
                    showTransientPanel()
                } else if case .idle = state,
                          activeRecordingSource == nil {
                    activeWorkflow = .dictation

                    if panelPresentationMode == .transient, isPanelVisible {
                        panelHideTask = Task { @MainActor [weak self] in
                            try? await Task.sleep(for: .milliseconds(180))
                            guard let self else { return }
                            guard case .idle = dictationViewModel.state else { return }
                            guard panelPresentationMode == .transient else { return }
                            hidePanel()
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func startDictationCapture(source: PrimaryActionSource) {
        activeContextSnapshot = captureTargetApplicationSnapshot()
        activeWorkflow = .dictation
        activeRecordingSource = source
        showTransientPanel()
        dictationViewModel.startCapture()
    }

    private func prepareForWorkflowStart() -> Bool {
        switch dictationViewModel.state {
        case .idle:
            return true
        case .result, .error:
            dictationViewModel.send(.resetTapped)
            return true
        case .listening, .processing:
            return false
        }
    }

    private func presentWorkflowError(_ message: String) {
        activeRecordingSource = nil
        dictationViewModel.send(.transcriptionFailed(message))
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

    private func selectedTextIfAvailable() -> String? {
        let selectedText = textInjectionService.selectedText()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let selectedText, !selectedText.isEmpty else { return nil }
        return selectedText
    }

    private func handleCompletedResult(
        text: String,
        workflow: CaptureWorkflow
    ) async -> MacDictationCaptureCoordinator.CaptureOutcome {
        let metadata = makeHistoryMetadata(for: workflow)

        if workflow.isSelectionReplacement {
            return await handleSelectedTextReplacementResult(text: text, metadata: metadata)
        }

        return await captureCoordinator.handleCompletedCapture(
            text: text,
            existingHistory: history,
            metadata: metadata,
            targetApplication: lastTargetApplication,
            settings: captureSettings
        ) { [weak self] in
            self?.showTransientPanel()
        }
    }

    private func handleSelectedTextReplacementResult(
        text: String,
        metadata: TranscriptionRecordMetadata
    ) async -> MacDictationCaptureCoordinator.CaptureOutcome {
        let prepared = await captureCoordinator.prepareCapture(
            text: text,
            metadata: metadata,
            existingHistory: history
        )
        let keepResultInClipboard = captureSettings.shouldCopyToClipboard
        let didReplaceSelection = await textInjectionService.replaceSelectedText(
            text,
            into: lastTargetApplication,
            keepResultInClipboard: keepResultInClipboard
        )

        if !didReplaceSelection {
            if !textInjectionService.isAvailable {
                textInjectionService.requestAccessIfNeeded()
            }

            if captureSettings.shouldRevealPanelOnCapture {
                showTransientPanel()
            }
        }

        let copiedRecordID: UUID? = (keepResultInClipboard || !didReplaceSelection) ? prepared.record.id : nil
        return .init(history: prepared.history, copiedRecordID: copiedRecordID)
    }

    func didCopyRecord(_ record: TranscriptionRecord) -> Bool {
        lastCopiedRecordID == record.id
    }

    private func configureDefaults() {
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

        if UserDefaults.standard.string(forKey: MacPreferences.historyRetentionPeriod) == nil {
            settingsStore.saveHistoryRetentionPeriod(.thirtyDays)
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

    private func restoreHistory() {
        Task { [captureCoordinator] in
            let records = await captureCoordinator.loadHistory()
            await MainActor.run { [weak self] in
                self?.history = records
            }
        }
    }

    private func persistHistory() {
        let snapshot = history
        captureCoordinator.persistHistory(snapshot)
    }

    @discardableResult
    private func captureTargetApplicationSnapshot() -> FocusedAppSnapshot {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let application: NSRunningApplication?
        if let frontmostApplication,
           frontmostApplication.bundleIdentifier != Bundle.main.bundleIdentifier {
            application = frontmostApplication
        } else {
            application = lastTargetApplication
        }

        guard let application else {
            return activeContextSnapshot ?? FocusedAppSnapshot(bundleID: nil, appName: nil)
        }

        lastTargetApplication = application
        return FocusedAppSnapshot(
            bundleID: application.bundleIdentifier,
            appName: application.localizedName
        )
    }

    private var settingsSnapshot: DictationSettingsSnapshot {
        settingsStore.loadSnapshot()
    }

    private var currentShowInDockPreference: Bool {
        UserDefaults.standard.object(forKey: MacPreferences.showInDock) as? Bool ?? false
    }

    private func prepareForSettingsPresentation() {
        if !currentShowInDockPreference {
            shouldRestoreAccessoryModeAfterSettings = true
        }

        MacAppBehaviorController.applyDockVisibility(showInDock: true)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var captureSettings: MacDictationCaptureCoordinator.CaptureSettings {
        MacDictationCaptureCoordinator.CaptureSettings(
            shouldCopyToClipboard: UserDefaults.standard.bool(forKey: MacPreferences.copyToClipboardOnCapture),
            shouldAutoPaste: UserDefaults.standard.bool(forKey: MacPreferences.autoPasteOnCapture),
            shouldRevealPanelOnCapture: UserDefaults.standard.bool(forKey: MacPreferences.revealPanelOnCapture)
        )
    }

    private func handleMediaTransition(from previousState: DictationState, to newState: DictationState) {
        if settingsSnapshot.interactionSoundsEnabled {
            if case .idle = previousState, case .listening = newState {
                interactionSoundPlayer.playStart(preset: settingsSnapshot.interactionSoundPreset)
            } else if isActiveDictationState(previousState),
                      shouldResumeMedia(after: newState),
                      !matchesErrorState(newState) {
                interactionSoundPlayer.playFinish(preset: settingsSnapshot.interactionSoundPreset)
            }
        }

        if case .listening = newState {
            if case .listening = previousState {
                return
            }

            if settingsSnapshot.shouldPauseMediaDuringDictation {
                mediaPlaybackController.pausePlaybackIfNeeded()
            }
            return
        }

        if isActiveDictationState(previousState),
           shouldResumeMedia(after: newState) {
            mediaPlaybackController.resumePlaybackIfNeeded()
        }
    }

    private func isActiveDictationState(_ state: DictationState) -> Bool {
        switch state {
        case .listening, .processing:
            return true
        case .idle, .result, .error:
            return false
        }
    }

    private func shouldResumeMedia(after state: DictationState) -> Bool {
        switch state {
        case .idle, .result, .error:
            return true
        case .listening, .processing:
            return false
        }
    }

    private var inputMonitoringGranted: Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess()
        }

        return true
    }

    private func matchesErrorState(_ state: DictationState) -> Bool {
        if case .error = state {
            return true
        }

        return false
    }

    private func makeHistoryMetadata(for workflow: CaptureWorkflow) -> TranscriptionRecordMetadata {
        let snapshot = settingsSnapshot
        let contextSnapshot = activeContextSnapshot ?? captureTargetApplicationSnapshot()

        let kind: TranscriptionRecordKind
        let source: TranscriptionRecordSource

        switch workflow {
        case .dictation:
            kind = snapshot.isRewriteEnabled ? .rewrite : .dictation
            source = .speech
        case .translationFromSpeech:
            kind = .translation
            source = .speech
        case .translationFromSelection:
            kind = .translation
            source = .selection
        case .rewriteFromSelection:
            kind = .rewrite
            source = .selection
        }

        let transcriptionModel = snapshot.openAIConfiguration?.transcriptionModel

        return TranscriptionRecordMetadata(
            kind: kind,
            source: source,
            transcriptionProvider: snapshot.provider.displayName,
            transcriptionModel: transcriptionModel,
            translationModel: kind == .translation ? snapshot.openAIConfiguration?.translationModel : nil,
            rewriteModel: kind == .rewrite ? snapshot.openAIConfiguration?.rewriteModel : nil,
            targetLanguage: kind == .translation ? snapshot.translationTargetLanguage.title : nil,
            focusedAppName: contextSnapshot.appName,
            focusedBundleID: contextSnapshot.bundleID
        )
    }
}
#endif
