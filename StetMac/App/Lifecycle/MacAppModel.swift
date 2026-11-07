#if os(macOS)
    import Combine
    import Foundation
    import os
    import AppKit
    import StetVisuals

    @MainActor
    final class MacAppModel: ObservableObject, MacDictationCommandsCoordinating, MacSettingsShellCoordinating,
        MacAppPresentationModeling, MacCalendarSettingsAppModeling, MacMeetingCoordinating
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
        private let meetingWorkflow: MacMeetingWorkflowController
        let meetingSpeakerSettings: MeetingSpeakerSettings
        private let meetingRecordingRuntime: MacMeetingRecordingRuntime?
        private let calendarSyncController: CalendarSyncController?
        private var mcpServerStateHandler: (@MainActor (StetMCPServerState) -> Void)?

        var meetingRecordingPhase: MacMeetingRecordingPhase { meetingWorkflow.phase }
        @Published private(set) var mcpServerState: StetMCPServerState = .disabled
        @Published private(set) var calendarSyncState: CalendarSyncState = .disabled

        private var cancellables = Set<AnyCancellable>()

        init(
            speechService: any SpeechService,
            clipboardService: any ClipboardService,
            textInjectionService: any TextInjectionService,
            mediaPlaybackController: any MediaPlaybackControlling,
            systemAudioMuting: (any SystemAudioMuting)? = nil,
            settingsStore: DictationSettingsStore = DictationSettingsStore(),
            captureCoordinator: MacDictationCaptureCoordinator? = nil,
            mcpServerController: StetMCPServerController? = nil,
            meetingRecordingRuntime: MacMeetingRecordingRuntime? = nil,
            liveMeetingPhaseStore: MCPLiveMeetingPhaseStore? = nil,
            expectedMeetingCoordinator: (any ExpectedMeetingServing)? = nil,
            calendarSyncController: CalendarSyncController? = nil,
            meetingSpeakerSettings: MeetingSpeakerSettings? = nil
        ) {
            let bootstrapper = MacAppBootstrapper(settingsStore: settingsStore)
            let captureCoordinator =
                captureCoordinator
                ?? MacDictationCaptureCoordinator(
                    clipboardService: clipboardService,
                    textInjectionService: textInjectionService
                )
            let interactionSoundPlayer = InteractionSoundPlayer()
            MacDictationCompletionNotificationService.shared.installDelegateIfNeeded()
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
            self.meetingRecordingRuntime = meetingRecordingRuntime
            let speakerSettings = meetingSpeakerSettings ?? MeetingSpeakerSettings(store: MeetingSpeakerModelStore())
            self.meetingSpeakerSettings = speakerSettings
            self.meetingWorkflow = MacMeetingWorkflowController(
                recording: meetingRecordingRuntime,
                expectedMeetings: expectedMeetingCoordinator,
                publishLivePhase: { liveMeetingPhaseStore?.update($0) },
                notifyPhase: { previous, phase in
                    await MacDictationCompletionNotificationService.shared.notifyMeetingPhase(from: previous, to: phase)
                },
                prepareSpeakers: { await MacMeetingSpeakerPreflight.prepare(speakerSettings) }
            )
            self.calendarSyncController = calendarSyncController
            self.mcpServerState = mcpServerController?.state ?? .disabled
            let launchConfiguration = bootstrapper.prepareForLaunch()
            if !ProcessInfo.processInfo.isRunningTests {
                DictationWordCountMigration.migrateIfNeeded()
            }
            sessionController.onChange = { [weak self] in
                self?.objectWillChange.send()
            }

            appearanceSettingsViewModel.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
            sessionController.activate(presentationModel: self, showInDock: launchConfiguration.showInDock)
            mcpServerController?.onStateChange = { [weak self] state in
                self?.mcpServerState = state
                self?.mcpServerStateHandler?(state)
            }
            mcpServerController?.startIfEnabled()

            let notificationService = MacDictationCompletionNotificationService.shared
            notificationService.onStartExpectedMeeting = { [weak self] id in
                self?.meetingWorkflow.startExpectedMeeting(id: id)
            }
            notificationService.onSkipExpectedMeeting = { [weak self] id in
                self?.meetingWorkflow.skipExpectedMeeting(id: id)
            }
            meetingWorkflow.restoreReminders()
            if let calendarSyncController {
                calendarSyncController.onStateChange = { [weak self] state in
                    self?.calendarSyncState = state
                }
                if UserDefaults.standard.bool(forKey: MacPreferences.calendarMeetingsEnabled) {
                    Task { await calendarSyncController.start() }
                }
            }

            sessionController.isMeetingSessionBusy = { [weak self] in
                self?.isMeetingBusy ?? false
            }
            sessionController.onMeetingHotkey = { [weak self] in
                self?.toggleMeetingRecording()
            }

            meetingWorkflow.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
            let meetingWorkflow = meetingWorkflow
            Task { await meetingWorkflow.observeRecording() }

        }

        deinit {
            let meetingRecordingRuntime = meetingRecordingRuntime
            let calendarSyncController = calendarSyncController
            Task {
                await calendarSyncController?.stop()
                await meetingRecordingRuntime?.stop()
            }
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

        var isMeetingBusy: Bool { meetingWorkflow.isBusy }

        var isMeetingRecording: Bool {
            if case .recording = meetingRecordingPhase {
                return true
            }
            return false
        }

        var meetingStatusText: String {
            switch meetingRecordingPhase {
            case .idle:
                return "Meeting recording idle"
            case .starting:
                return "Starting microphone and system audio recording"
            case .recording(_, let folderName):
                return "Recording meeting · \(folderName)"
            case .processing:
                return String(localized: "Recording saved · Preparing transcription")
            case .separatingSpeakers:
                return String(localized: "Recording saved · Separating speakers")
            case .transcribing:
                return String(localized: "Recording saved · Transcribing")
            case .failed(let message):
                return message
            }
        }

        var meetingMenuSymbolName: String {
            switch meetingRecordingPhase {
            case .recording:
                return "record.circle.fill"
            case .starting, .processing, .separatingSpeakers, .transcribing:
                return "hourglass"
            case .failed:
                return "exclamationmark.triangle"
            case .idle:
                return "record.circle"
            }
        }

        var meetingToggleTitle: String {
            switch meetingRecordingPhase {
            case .idle, .failed:
                return "Start Meeting Recording"
            case .starting:
                return "Starting meeting recording"
            case .recording:
                return "Stop Meeting Recording"
            case .processing, .separatingSpeakers, .transcribing:
                return "Processing meeting"
            }
        }

        var canToggleMeetingRecording: Bool {
            switch meetingRecordingPhase {
            case .starting, .processing, .separatingSpeakers, .transcribing:
                return false
            case .idle, .recording, .failed:
                return true
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

        func toggleMeetingRecording() {
            meetingWorkflow.toggle()
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

        func setMCPServerEnabled(_ enabled: Bool) async -> StetMCPServerState {
            guard let mcpServerController else { return .disabled }
            await mcpServerController.setEnabled(enabled)
            return mcpServerController.state
        }

        func setMCPServerStateHandler(_ handler: @escaping @MainActor (StetMCPServerState) -> Void) {
            mcpServerStateHandler = handler
            handler(mcpServerState)
        }

        var isCalendarMeetingsEnabled: Bool {
            UserDefaults.standard.bool(forKey: MacPreferences.calendarMeetingsEnabled)
        }

        var calendarAuthorizationStatus: CalendarAuthorizationStatus {
            calendarSyncController?.authorizationStatus ?? .denied
        }

        var selectedCalendarIDs: Set<String> {
            calendarSyncController?.selectedCalendarIDs ?? []
        }

        func availableCalendars() throws -> [CalendarRecord] {
            try calendarSyncController?.calendars() ?? []
        }

        func setCalendarMeetingsEnabled(_ enabled: Bool) async {
            guard let calendarSyncController else { return }
            if enabled {
                do {
                    guard try await calendarSyncController.requestAccess() else {
                        await calendarSyncController.start()
                        return
                    }
                    UserDefaults.standard.set(true, forKey: MacPreferences.calendarMeetingsEnabled)
                    await calendarSyncController.start()
                } catch {
                    calendarSyncState = .failed(error.localizedDescription)
                }
            } else {
                UserDefaults.standard.set(false, forKey: MacPreferences.calendarMeetingsEnabled)
                await calendarSyncController.stopAndClear()
            }
        }

        func setSelectedCalendarIDs(_ ids: Set<String>) async {
            await calendarSyncController?.setSelectedCalendarIDs(ids)
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
